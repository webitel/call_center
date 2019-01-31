package sqlstore


import (
	"github.com/webitel/call_center/store"
	"fmt"
	"time"
	"runtime"
	"bytes"
	"strconv"
)

type SqlQueueStore struct {
	SqlStore
}

func getGID() uint64 {
	b := make([]byte, 64)
	b = b[:runtime.Stack(b, false)]
	b = bytes.TrimPrefix(b, []byte("goroutine "))
	b = b[:bytes.IndexByte(b, ' ')]
	n, _ := strconv.ParseUint(string(b), 10, 64)
	return n
}

func testRemove(sqlStore SqlStore)  {

	go func() {
		var err error
		for {
			_, err = sqlStore.GetMaster().Exec(`UPDATE cc_member_attempt
SET    state = -1
WHERE  id in (
         SELECT id
         FROM   cc_member_attempt
         WHERE  state = 0
         AND    pg_try_advisory_xact_lock(id)
         order by created_at desc , weight asc
         LIMIT  1

         FOR    UPDATE
         )
RETURNING *`)

			if err != nil {
				panic(err)
			}

			time.Sleep(time.Millisecond * 500)
		}
	}()
}

func NewSqlQueueStore(sqlStore SqlStore) store.QueueStore {
	us := &SqlQueueStore{sqlStore}
	testRemove(sqlStore)
	go func() {
		var err error
		var count int64
		fmt.Printf("Start [%v]\n", getGID())
		for {
			count, err = sqlStore.GetMaster().SelectInt(`select * from f_add_task_for_call()`)
			if err != nil {
				panic(err)
			}
			if count > 0  {
				fmt.Printf("New tasks %v [%v]\n", count, getGID())
			}
			time.Sleep(time.Millisecond * 200)
		}
	}()

	return us
}

func (self *SqlQueueStore) CreateIndexesIfNotExists() {

}