package store

type LayeredStoreSupplierResult struct {
}

func NewSupplierResult() *LayeredStoreSupplierResult {
	return &LayeredStoreSupplierResult{}
}

type LayeredStoreSupplier interface {
	//
	// Control
	//
	SetChainNext(LayeredStoreSupplier)
	Next() LayeredStoreSupplier
}
