package utils

import (
	"slices"
	"testing"
)

func TestFilterSlice(t *testing.T) {
	tests := []struct {
		name string
		input     []int
		predicate func(int) bool
		want      []int
	}{
		{
			name: "Empty input slice",
			input: []int{},
			predicate: func(i int) bool { return true },
			want: []int{},
		},
		{
			name: "Slice with no elements satisfying the predicate",
			input: []int{1, 2, 3, 4, 5},
			predicate: func(i int) bool { return i > 5 },
			want: []int{},
		},
		{
			name: "Slice with elements satisfying the predicate",
			input: []int{1, 2, 3, 4, 5},
			predicate: func(i int) bool { return i < 4 },
			want: []int{1, 2, 3},
		},
		{
			name: "Slice with all elements satisfying the predicate",
			input: []int{1, 2, 3, 4, 5},
			predicate: func(i int) bool { return true },
			want: []int{1, 2, 3, 4, 5},
		},
	}

	
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			got := FilterSlice(tt.input, tt.predicate)
			if !slices.Equal(got, tt.want) {
				t.Errorf("FilterSlice() = %d, want %d",  got, tt.want)
			}
		})
	}
}
