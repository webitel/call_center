package utils

import (
	"sync"
)

type PoolJob interface {
	Execute()
}

type Pool struct {
	mu   sync.Mutex
	size int
	jobs chan PoolJob
	kill chan struct{}
	wg   sync.WaitGroup
}

func NewPool(workers int, queueCount int) *Pool {
	pool := &Pool{
		jobs: make(chan PoolJob, queueCount),
		kill: make(chan struct{}),
	}
	pool.Resize(workers)
	return pool
}

func (p *Pool) worker() {
	defer p.wg.Done()
	for {
		select {
		case task, ok := <-p.jobs:
			if !ok {
				return
			}
			task.Execute()
		case <-p.kill:
			return
		}
	}
}

func (p *Pool) Resize(n int) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for p.size < n {
		p.size++
		p.wg.Add(1)
		go p.worker()
	}
	for p.size > n {
		p.size--
		p.kill <- struct{}{}
	}
}

func (p *Pool) Close() {
	close(p.jobs)
}

func (p *Pool) Wait() {
	p.wg.Wait()
}

func (p *Pool) Exec(task PoolJob) {
	p.jobs <- task
}

func (p *Pool) ChannelJobs() chan PoolJob {
	return p.jobs
}
