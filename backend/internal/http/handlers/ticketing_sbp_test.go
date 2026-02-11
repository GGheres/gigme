package handlers

import "testing"

func TestNormalizeProviderStatus(t *testing.T) {
	t.Parallel()

	cases := []struct {
		in   string
		want string
	}{
		{in: "Accepted", want: "PAID"},
		{in: "NotStarted", want: "PENDING"},
		{in: "Received", want: "PENDING"},
		{in: "InProgress", want: "PENDING"},
		{in: "Rejected", want: "FAILED"},
		{in: "", want: "UNKNOWN"},
	}

	for _, tc := range cases {
		tc := tc
		t.Run(tc.in, func(t *testing.T) {
			t.Parallel()
			if got := normalizeProviderStatus(tc.in); got != tc.want {
				t.Fatalf("normalizeProviderStatus(%q) = %q, want %q", tc.in, got, tc.want)
			}
		})
	}
}
