package queue

func Assert(src interface{}) {
	if src == nil {
		panic("assert error")
	}
}
