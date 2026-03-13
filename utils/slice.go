package utils

// FilterSlice filters the given slice and returns a new slice containing only the elements
// for which the given predicate function returns true.
func FilterSlice[T any](input []T, predicate func(T) bool) []T {
	var result []T
	for _, item := range input {
		if predicate(item) {
			result = append(result, item)
		}
	}
	return result
}