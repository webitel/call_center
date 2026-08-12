package queue

type RecordingQueue struct {
	Recordings       bool `json:"recordings"`
	RecordMono       bool `json:"record_mono"`
	RecordAll        bool `json:"record_all"`
	RecordAllSetting bool `json:"record_all_setting"`
}

func NewRecordingQueue(recordings, recordMono, recordAll bool) *RecordingQueue {
	return &RecordingQueue{
		Recordings: recordings,
		RecordMono: recordMono,
		RecordAll:  recordAll,
	}
}

func (q *RecordingQueue) HasRecording() bool {
	return q.Recordings || q.RecordAllSetting
}
