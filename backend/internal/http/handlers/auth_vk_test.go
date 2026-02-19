package handlers

import "testing"

func TestVKExternalTelegramID(t *testing.T) {
	tests := []struct {
		name string
		in   int64
		want int64
	}{
		{name: "positive_id", in: 123, want: -123},
		{name: "zero_fallback", in: 0, want: -1},
		{name: "negative_fallback", in: -99, want: -1},
	}

	for _, tc := range tests {
		tc := tc
		t.Run(tc.name, func(t *testing.T) {
			got := vkExternalTelegramID(tc.in)
			if got != tc.want {
				t.Fatalf("vkExternalTelegramID(%d) = %d, want %d", tc.in, got, tc.want)
			}
		})
	}
}
