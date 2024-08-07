package governor

import (
	"std"
	"testing"
	"gno.land/p/demo/json"
	"gno.land/p/demo/ufmt"
)

func TestParseCallsFromJSON(t *testing.T) {
	tests := []struct {
		name    string
		input   string
		want    []Call
		wantErr bool
	}{
		{
			name:  "Valid single call",
			input: `[{"to":"g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5","selector":1,"calldata":"test"}]`,
			want: []Call{
				{
					To:       std.Address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"),
					Selector: 1,
					Calldata: []byte("test"),
				},
			},
			wantErr: false,
		},
		{
			name:  "Valid multiple calls",
			input: `[{"to":"g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5","selector":1,"calldata":"test1"},{"to":"g1sss7jjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjj","selector":2,"calldata":"test2"}]`,
			want: []Call{
				{
					To:       std.Address("g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"),
					Selector: 1,
					Calldata: []byte("test1"),
				},
				{
					To:       std.Address("g1sss7jjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjjj"),
					Selector: 2,
					Calldata: []byte("test2"),
				},
			},
			wantErr: false,
		},
		{
			name:    "Not an array",
			input:   `{"to":"g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5","selector":1,"calldata":"test"}`,
			want:    nil,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			node, err := json.Unmarshal([]byte(tt.input))
			if err != nil {
				t.Fatalf("Failed to unmarshal JSON: %v", err)
			}

			got, err := parseCallsFromJSON(node)

			if (err != nil) != tt.wantErr {
				t.Errorf("parseCallsFromJSON() error = %v, wantErr %v", err, tt.wantErr)
				return
			}

			if !tt.wantErr {
				if len(got) != len(tt.want) {
					t.Errorf("parseCallsFromJSON() got %d calls, want %d", len(got), len(tt.want))
					return
				}

				for i, call := range got {
					if call.To != tt.want[i].To {
						t.Errorf("Call %d: To = %v, want %v", i, call.To, tt.want[i].To)
					}
					if call.Selector != tt.want[i].Selector {
						t.Errorf("Call %d: Selector = %v, want %v", i, call.Selector, tt.want[i].Selector)
					}
					if string(call.Calldata) != string(tt.want[i].Calldata) {
						t.Errorf("Call %d: Calldata = %v, want %v", i, string(call.Calldata), string(tt.want[i].Calldata))
					}
				}
			}
		})
	}
}