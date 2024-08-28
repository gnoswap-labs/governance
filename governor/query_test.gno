package governor

import (
	"std"
	"testing"

	"gno.land/p/demo/testutils"
	"gno.land/p/demo/json"
	"gno.land/p/demo/ufmt"
)

func TestParseCallsFromJSON(t *testing.T) {
	testAddr1 := testutils.TestAddress("test1")
	testAddr2 := testutils.TestAddress("test2")

	tests := []struct {
		name    string
		input   string
		want    []Call
		wantErr bool
	}{
		{
			name:  "Valid single call",
			input: ufmt.Sprintf(
				`[{"to":"%s","function_name":"Foo","calldata":"test"}]`,
				testAddr1.String(),
			),
			want: []Call{
				{
					To:       testAddr1,
					FunctionName: "Foo",
					Calldata: "test",
				},
			},
			wantErr: false,
		},
		{
			name:  "Valid multiple calls",
			input: ufmt.Sprintf(
				`[{"to":"%s","function_name":"Foo","calldata":"test1"},{"to":"%s","function_name":"Bar","calldata":"test2"}]`,
				testAddr1.String(),
				testAddr2.String(),
			),
			want: []Call{
				{
					To:       testAddr1,
					FunctionName: "Foo",
					Calldata: "test1",
				},
				{
					To:       testAddr2,
					FunctionName: "Bar",
					Calldata: "test2",
				},
			},
			wantErr: false,
		},
		{
			name:    "Not an array",
			input: ufmt.Sprintf(`{"to":"%s","function_name":"Foo","calldata":"test"}`, testAddr1.String()),
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
					if call.FunctionName != tt.want[i].FunctionName {
						t.Errorf("Call %d: FunctionName = %v, want %v", i, call.FunctionName, tt.want[i].FunctionName)
					}
					if call.Calldata != tt.want[i].Calldata {
						t.Errorf("Call %d: Calldata = %v, want %v", i, call.Calldata, tt.want[i].Calldata)
					}
				}
			}
		})
	}
}
