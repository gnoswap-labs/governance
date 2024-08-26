package governor

import (
	"bytes"
	"std"
	"testing"
	"time"

	"gno.land/p/demo/json"
	"gno.land/p/demo/testutils"
	"gno.land/p/demo/ufmt"
	u256"gno.land/p/demo/uint256"
)

func _setupTestConfig(t *testing.T) {
	testConfig := Config{
		VotingStartDelay:              100,
		VotingPeriod:                  200,
		VotingWeightSmoothingDuration: 300,
		Quorum:                        400,
		ProposalCreationThreshold:     500,
		ExecutionDelay:                600,
		ExecutionWindow:               700,
	}
	mockStaker := &MockStaker{
		averageDelegated: u256.NewUint(1000),
	}

	Init(mockStaker, testConfig)
}

func TestGetConfig(t *testing.T) {
	_setupTestConfig(t)

	jsonStr := GetConfig()

	node, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	votingStartDelay, err := node.MustKey("VotingStartDelay").Value()
	if err != nil {
		t.Fatalf("Failed to get VotingStartDelay: %v", err)
	}
	if votingStartDelay != float64(100) {
		t.Errorf("Expected VotingStartDelay to be 100, but got %v", votingStartDelay)
	}

	votingPeriod, err := node.MustKey("VotingPeriod").Value()
	if err != nil {
		t.Fatalf("Failed to get VotingPeriod: %v", err)
	}
	if votingPeriod != float64(200) {
		t.Errorf("Expected VotingPeriod to be 200, but got %v", votingPeriod)
	}

	votingWeightSmoothingDuration, err := node.MustKey("VotingWeightSmoothingDuration").Value()
	if err != nil {
		t.Fatalf("Failed to get VotingWeightSmoothingDuration: %v", err)
	}
	if votingWeightSmoothingDuration != float64(300) {
		t.Errorf("Expected VotingWeightSmoothingDuration to be 300, but got %v", votingWeightSmoothingDuration)
	}

	quorum, err := node.MustKey("Quorum").Value()
	if err != nil {
		t.Fatalf("Failed to get Quorum: %v", err)
	}
	if quorum != float64(400) {
		t.Errorf("Expected Quorum to be 400, but got %v", quorum)
	}

	proposalCreationThreshold, err := node.MustKey("ProposalCreationThreshold").Value()
	if err != nil {
		t.Fatalf("Failed to get ProposalCreationThreshold: %v", err)
	}
	if proposalCreationThreshold != float64(500) {
		t.Errorf("Expected ProposalCreationThreshold to be 500, but got %v", proposalCreationThreshold)
	}

	executionDelay, err := node.MustKey("ExecutionDelay").Value()
	if err != nil {
		t.Fatalf("Failed to get ExecutionDelay: %v", err)
	}
	if executionDelay != float64(600) {
		t.Errorf("Expected ExecutionDelay to be 600, but got %v", executionDelay)
	}

	executionWindow, err := node.MustKey("ExecutionWindow").Value()
	if err != nil {
		t.Fatalf("Failed to get ExecutionWindow: %v", err)
	}
	if executionWindow != float64(700) {
		t.Errorf("Expected ExecutionWindow to be 700, but got %v", executionWindow)
	}
}

func TestConfigWithVersion(t *testing.T) {
	_setupTestConfig(t)

	jsonStr := GetConfigWithVersion()

	expectedJSON := `{"config":{"VotingStartDelay":100,"VotingPeriod":200,"VotingWeightSmoothingDuration":300,"Quorum":400,"ProposalCreationThreshold":500,"ExecutionDelay":600,"ExecutionWindow":700},"version":0}`
	if jsonStr != expectedJSON {
		t.Errorf("GetConfigWithVersion() = %v, want %v", jsonStr, expectedJSON)
	}

	node, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	println(node.String())
}

func TestGetProposal(t *testing.T) {
	_setupTestConfig(t)

	testProposalID := "test_proposal_1"
	testProposer := testutils.TestAddress("test_proposer")
	testProposal := ProposalInfo{
		CallsHash: "test_calls_hash",
		Proposer:  testProposer,
		ExecutionState: ExecutionState{
			Created:  1000,
			Executed: 0,
			Canceled: 0,
		},
		Yea:           u256.NewUint(1000),
		Nay:           u256.NewUint(500),
		ConfigVersion: 1,
	}

	gGovernor.proposals.Set(testProposalID, testProposal)

	jsonStr := GetProposal(testProposalID)
	expectedJSON := `{"call_hash":"test_calls_hash","proposer":"g1w3jhxazlwpex7ur0wdjhyh6lta047h6l7atze0","execution_state":{"created":1000,"executed":0,"canceled":0},"yea":1000,"nay":500,"config_version":1}`

	if jsonStr != expectedJSON {
		t.Errorf("GetProposal() = %v, want %v", jsonStr, expectedJSON)
	}

	node, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	if node.String() != expectedJSON {
		t.Errorf("GetProposal() = %v, want %v", node.String(), expectedJSON)
	}
}

func TestGetProposalWithConfig(t *testing.T) {
	_setupTestConfig(t)

	testProposalID := "test_proposal_1"
	testProposer := testutils.TestAddress("test_proposer")

	testProposal := ProposalInfo{
		CallsHash: "test_calls_hash",
		Proposer:  testProposer,
		ExecutionState: ExecutionState{
			Created:  1000,
			Executed: 0,
			Canceled: 0,
		},
		Yea:           u256.NewUint(1000),
		Nay:           u256.NewUint(500),
		ConfigVersion: 1,
	}

	gGovernor.proposals.Set(testProposalID, testProposal)

	jsonStr := GetProposalWithConfig(testProposalID)
	expectedJSON := `{"config":{"VotingStartDelay":100,"VotingPeriod":200,"VotingWeightSmoothingDuration":300,"Quorum":400,"ProposalCreationThreshold":500,"ExecutionDelay":600,"ExecutionWindow":700},"proposal":{"call_hash":"test_calls_hash","proposer":"g1w3jhxazlwpex7ur0wdjhyh6lta047h6l7atze0","execution_state":{"created":1000,"executed":0,"canceled":0},"yea":1000,"nay":500,"config_version":1}}`
	if jsonStr != expectedJSON {
		t.Errorf("GetProposalWithConfig() = %v, want %v", jsonStr, expectedJSON)
	}

	node, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	keys := node.UniqueKeyLists()
	if len(keys) != 18 {
		t.Fatalf("Expected 18 keys, but got %v", len(keys))
	}

	println(keys)
}

func TestGetVote(t *testing.T) {
	_setupTestConfig(t)

	testProposalID := "test_proposal_1"
	testVoter := testutils.TestAddress("test_voter").String()
	voteKey := testProposalID + ":" + testVoter
	gGovernor.vote.Set(voteKey, uint8(3)) // Voted in favor

	jsonStr := GetVote(testProposalID, testVoter)

	node, err := json.Unmarshal([]byte(jsonStr))
	if err != nil {
		t.Fatalf("Failed to unmarshal JSON: %v", err)
	}

	keys := node.UniqueKeyLists()
	if len(keys) != 3 {
		t.Fatalf("Expected 3 keys, but got %v", len(keys))
	}

	id, err := node.MustKey("id").Value()
	if err != nil {
		t.Fatalf("Failed to get id: %v", err)
	}
	if id != testProposalID {
		t.Errorf("Expected id to be '%s', but got %v", testProposalID, id)
	}

	voter, err := node.MustKey("voter").Value()
	if err != nil {
		t.Fatalf("Failed to get voter: %v", err)
	}
	if voter != testVoter {
		t.Errorf("Expected voter to be '%s', but got %v", testVoter, voter)
	}

	vote, err := node.MustKey("vote").Value()
	if err != nil {
		t.Fatalf("Failed to get vote: %v", err)
	}
	if vote != float64(3) {
		t.Errorf("Expected vote to be 3, but got %v", vote)
	}
}
