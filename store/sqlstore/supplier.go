package sqlstore

import (
	"context"
	dbsql "database/sql"
	"errors"
	"fmt"
	sqltrace "log"
	"os"
	"time"

	"encoding/json"
	"github.com/go-gorp/gorp"
	"github.com/lib/pq"
	"github.com/webitel/call_center/model"
	"github.com/webitel/call_center/store"
	"github.com/webitel/wlog"
	"sync/atomic"
)

const (
	DB_PING_ATTEMPTS     = 150 // todo
	DB_PING_TIMEOUT_SECS = 10
)

const (
	EXIT_CREATE_TABLE = 100
	EXIT_DB_OPEN      = 101
	EXIT_PING         = 102
	EXIT_NO_DRIVER    = 103
)

type SqlSupplierOldStores struct {
	queue            store.QueueStore
	member           store.MemberStore
	outboundResource store.OutboundResourceStore
	agent            store.AgentStore
	team             store.TeamStore
	cluster          store.ClusterStore
	gateway          store.GatewayStore
	call             store.CallStore
	statistic        store.StatisticStore
	trigger          store.TriggerStore
}

type SqlSupplier struct {
	rrCounter      int64
	srCounter      int64
	next           store.LayeredStoreSupplier
	master         *gorp.DbMap
	replicas       []*gorp.DbMap
	searchReplicas []*gorp.DbMap
	oldStores      SqlSupplierOldStores
	settings       *model.SqlSettings
	lockedToMaster bool
}

func NewSqlSupplier(settings model.SqlSettings) *SqlSupplier {
	supplier := &SqlSupplier{
		rrCounter: 0,
		srCounter: 0,
		settings:  &settings,
	}

	supplier.initConnection()

	supplier.oldStores.cluster = NewSqlClusterStore(supplier)

	supplier.oldStores.queue = NewSqlQueueStore(supplier)
	supplier.oldStores.member = NewSqlMemberStore(supplier)
	supplier.oldStores.outboundResource = NewSqlOutboundResourceStore(supplier)
	supplier.oldStores.agent = NewSqlAgentStore(supplier)
	supplier.oldStores.team = NewSqlTeamStore(supplier)
	supplier.oldStores.gateway = NewSqlGatewayStore(supplier)
	supplier.oldStores.call = NewSqlCallStore(supplier)
	supplier.oldStores.statistic = NewSqlStatisticStore(supplier)
	supplier.oldStores.trigger = NewSqlTriggerStore(supplier)

	err := supplier.GetMaster().CreateTablesIfNotExists()
	if err != nil {
		wlog.Critical(fmt.Sprintf("Error creating database tables: %v", err))
		time.Sleep(time.Second)
		os.Exit(EXIT_CREATE_TABLE)
	}

	supplier.oldStores.cluster.(*SqlClusterStore).CreateTableIfNotExists()
	supplier.oldStores.agent.(*SqlAgentStore).CreateTableIfNotExists()

	return supplier
}

func (s *SqlSupplier) SetChainNext(next store.LayeredStoreSupplier) {
	s.next = next
}

func (s *SqlSupplier) Next() store.LayeredStoreSupplier {
	return s.next
}

func (ss *SqlSupplier) GetAllConns() []*gorp.DbMap {
	all := make([]*gorp.DbMap, len(ss.replicas)+1)
	copy(all, ss.replicas)
	all[len(ss.replicas)] = ss.master
	return all
}

func setupConnection(con_type string, dataSource string, settings *model.SqlSettings) *gorp.DbMap {
	db, err := dbsql.Open(*settings.DriverName, dataSource)
	if err != nil {
		wlog.Critical(fmt.Sprintf("Failed to open SQL connection to err:%v", err.Error()))
		time.Sleep(time.Second)
		os.Exit(EXIT_DB_OPEN)
	}

	for i := 0; i < DB_PING_ATTEMPTS; i++ {
		wlog.Info(fmt.Sprintf("Pinging SQL %v database", con_type))
		ctx, cancel := context.WithTimeout(context.Background(), DB_PING_TIMEOUT_SECS*time.Second)
		defer cancel()
		err = db.PingContext(ctx)
		if err == nil {
			break
		} else {
			if i == DB_PING_ATTEMPTS-1 {
				wlog.Critical(fmt.Sprintf("Failed to ping DB, server will exit err=%v", err))
				time.Sleep(time.Second)
				os.Exit(EXIT_PING)
			} else {
				wlog.Error(fmt.Sprintf("Failed to ping DB retrying in %v seconds err=%v", DB_PING_TIMEOUT_SECS, err))
				time.Sleep(DB_PING_TIMEOUT_SECS * time.Second)
			}
		}
	}

	db.SetMaxIdleConns(*settings.MaxIdleConns)
	db.SetMaxOpenConns(*settings.MaxOpenConns)
	db.SetConnMaxLifetime(time.Duration(*settings.ConnMaxLifetimeMilliseconds) * time.Millisecond)

	var dbmap *gorp.DbMap

	if *settings.DriverName == model.DATABASE_DRIVER_POSTGRES {
		dbmap = &gorp.DbMap{Db: db, TypeConverter: typeConverter{}, Dialect: PostgresJSONDialect{}}
	} else {
		wlog.Critical("Failed to create dialect specific driver")
		time.Sleep(time.Second)
		os.Exit(EXIT_NO_DRIVER)
	}

	if settings.Trace {
		dbmap.TraceOn("[SQL]", sqltrace.New(os.Stdout, "", sqltrace.LstdFlags))
	}

	return dbmap
}

func (s *SqlSupplier) initConnection() {
	s.master = setupConnection("master", *s.settings.DataSource, s.settings)

	if len(s.settings.DataSourceReplicas) > 0 {
		s.replicas = make([]*gorp.DbMap, len(s.settings.DataSourceReplicas))
		for i, replica := range s.settings.DataSourceReplicas {
			s.replicas[i] = setupConnection(fmt.Sprintf("replica-%v", i), replica, s.settings)
		}
	}

	if len(s.settings.DataSourceSearchReplicas) > 0 {
		s.searchReplicas = make([]*gorp.DbMap, len(s.settings.DataSourceSearchReplicas))
		for i, replica := range s.settings.DataSourceSearchReplicas {
			s.searchReplicas[i] = setupConnection(fmt.Sprintf("search-replica-%v", i), replica, s.settings)
		}
	}
}

func (ss *SqlSupplier) GetMaster() *gorp.DbMap {
	return ss.master
}

func (ss *SqlSupplier) GetReplica() *gorp.DbMap {
	if len(ss.settings.DataSourceReplicas) == 0 || ss.lockedToMaster {
		return ss.GetMaster()
	}

	rrNum := atomic.AddInt64(&ss.rrCounter, 1) % int64(len(ss.replicas))
	return ss.replicas[rrNum]
}

func (ss *SqlSupplier) DriverName() string {
	return *ss.settings.DriverName
}

func (ss *SqlSupplier) Cluster() store.ClusterStore {
	return ss.oldStores.cluster
}

func (ss *SqlSupplier) OutboundResource() store.OutboundResourceStore {
	return ss.oldStores.outboundResource
}

func (ss *SqlSupplier) Queue() store.QueueStore {
	return ss.oldStores.queue
}

func (ss *SqlSupplier) Member() store.MemberStore {
	return ss.oldStores.member
}

func (ss *SqlSupplier) Agent() store.AgentStore {
	return ss.oldStores.agent
}

func (ss *SqlSupplier) Team() store.TeamStore {
	return ss.oldStores.team
}

func (ss *SqlSupplier) Gateway() store.GatewayStore {
	return ss.oldStores.gateway
}

func (ss *SqlSupplier) Call() store.CallStore {
	return ss.oldStores.call
}

func (ss *SqlSupplier) Statistic() store.StatisticStore {
	return ss.oldStores.statistic
}

func (ss *SqlSupplier) Trigger() store.TriggerStore {
	return ss.oldStores.trigger
}

type typeConverter struct{}

func (me typeConverter) ToDb(val interface{}) (interface{}, error) {

	switch t := val.(type) {
	case model.StringMap:
		return model.MapToJson(t), nil
	case map[string]string:
		return model.MapToJson(model.StringMap(t)), nil
	case model.StringArray:
		return model.ArrayToJson(t), nil
	case model.StringInterface:
		return model.StringInterfaceToJson(t), nil
	case map[string]interface{}:
		return model.StringInterfaceToJson(model.StringInterface(t)), nil
	}

	return val, nil
}

func (me typeConverter) FromDb(target interface{}) (gorp.CustomScanner, bool) {
	switch target.(type) {
	case *model.OutboundResourceParameters,
		*[]*model.MemberWaiting:
		binder := func(holder, target interface{}) error {
			s, ok := holder.(*[]byte)
			if !ok {
				return errors.New("store.sql.convert_object")
			}
			if *s == nil {
				return nil
			}
			return json.Unmarshal(*s, target)
		}
		return gorp.CustomScanner{Holder: &[]byte{}, Target: target, Binder: binder}, true
	case *model.Lookup,
		*model.RingtoneFile,
		*model.AgentChannel,
		*[]model.AgentChannel:
		binder := func(holder, target interface{}) error {
			s, ok := holder.(*string)
			if !ok {
				return errors.New("store.sql.convert_string_map")
			}
			b := []byte(*s)
			return json.Unmarshal(b, target)
		}
		return gorp.CustomScanner{Holder: new(string), Target: target, Binder: binder}, true

	case **model.RingtoneFile,
		*model.TriggerJobParameter,
		*[]*model.QueueHook:
		binder := func(holder, target interface{}) error {
			s, ok := holder.(*[]byte)
			if !ok {
				return errors.New("store.sql.convert_lookup")
			}
			if *s == nil {
				return nil
			}
			return json.Unmarshal(*s, target)
		}

		return gorp.CustomScanner{Holder: new([]byte), Target: target, Binder: binder}, true
	case *model.StringMap:
		binder := func(holder, target interface{}) error {
			s, ok := holder.(*string)
			if !ok {
				return errors.New("store.sql.convert_string_map")
			}
			b := []byte(*s)
			return json.Unmarshal(b, target)
		}
		return gorp.CustomScanner{Holder: new(string), Target: target, Binder: binder}, true
	case *map[string]string:
		binder := func(holder, target interface{}) error {
			s, ok := holder.(*string)
			if !ok {
				return errors.New("store.sql.convert_string_map")
			}
			b := []byte(*s)
			return json.Unmarshal(b, target)
		}
		return gorp.CustomScanner{Holder: new(string), Target: target, Binder: binder}, true
	case *model.StringArray:
		binder := func(holder, target interface{}) error {
			s, ok := holder.(*string)
			if !ok {
				return errors.New("store.sql.convert_string_array")
			}

			var a pq.StringArray

			if err := a.Scan(*s); err != nil {
				return err
			} else {
				*(target).(*model.StringArray) = model.StringArray(a)
				return nil
			}
		}
		return gorp.CustomScanner{Holder: new(string), Target: target, Binder: binder}, true
	case *model.StringInterface:
		binder := func(holder, target interface{}) error {
			s, ok := holder.(*string)
			if !ok {
				return errors.New("store.sql.convert_string_interface")
			}
			b := []byte(*s)
			return json.Unmarshal(b, target)
		}
		return gorp.CustomScanner{Holder: model.StringInterface{}, Target: target, Binder: binder}, true
	case *map[string]interface{}:
		binder := func(holder, target interface{}) error {
			s, ok := holder.(*string)
			if !ok {
				return errors.New("store.sql.convert_string_interface")
			}
			b := []byte(*s)
			return json.Unmarshal(b, target)
		}
		return gorp.CustomScanner{Holder: new(string), Target: target, Binder: binder}, true

	case *model.Int64Array, **model.Int64Array:
		binder := func(holder, target interface{}) error {
			s, ok := holder.(*[]byte)
			if !ok {
				return errors.New("store.sql.convert_int64_array")
			}
			var a pq.Int64Array

			if err := a.Scan(*s); err != nil {
				return err
			} else {
				*(target).(*model.Int64Array) = model.Int64Array(a)
				return nil
			}
		}
		return gorp.CustomScanner{Holder: new([]byte), Target: target, Binder: binder}, true
	}

	return gorp.CustomScanner{}, false
}
