package ticketing

import "testing"

// TestAggregateStats verifies aggregate stats behavior.
func TestAggregateStats(t *testing.T) {
	rows := []StatsRow{
		{OrderID: "o1", EventID: 1, EventTitle: "Event A", Status: "PAID", TotalCents: 10000, ItemType: "TICKET", ProductRef: "SINGLE", Quantity: 2},
		{OrderID: "o1", EventID: 1, EventTitle: "Event A", Status: "PAID", TotalCents: 10000, ItemType: "TRANSFER", ProductRef: "THERE", Quantity: 1},
		{OrderID: "o2", EventID: 1, EventTitle: "Event A", Status: "REDEEMED", TotalCents: 20000, ItemType: "TICKET", ProductRef: "GROUP2", Quantity: 1},
		{OrderID: "o3", EventID: 2, EventTitle: "Event B", Status: "CONFIRMED", TotalCents: 5000, ItemType: "TICKET", ProductRef: "SINGLE", Quantity: 1},
		{OrderID: "o4", EventID: 2, EventTitle: "Event B", Status: "PENDING", TotalCents: 5000, ItemType: "TICKET", ProductRef: "SINGLE", Quantity: 1},
	}

	global, perEvent := AggregateStats(rows)
	if global.PurchasedAmountCents != 35000 {
		t.Fatalf("expected global purchased=35000, got %d", global.PurchasedAmountCents)
	}
	if global.RedeemedAmountCents != 20000 {
		t.Fatalf("expected global redeemed=20000, got %d", global.RedeemedAmountCents)
	}
	if global.TicketTypeCounts["SINGLE"] != 3 {
		t.Fatalf("expected SINGLE=3, got %d", global.TicketTypeCounts["SINGLE"])
	}
	if global.TicketTypeCounts["GROUP2"] != 1 {
		t.Fatalf("expected GROUP2=1, got %d", global.TicketTypeCounts["GROUP2"])
	}
	if global.TransferDirectionCounts["THERE"] != 1 {
		t.Fatalf("expected THERE=1, got %d", global.TransferDirectionCounts["THERE"])
	}

	eventOne, ok := perEvent[1]
	if !ok {
		t.Fatalf("expected event 1 bucket")
	}
	if eventOne.PurchasedAmountCents != 30000 {
		t.Fatalf("expected event 1 purchased=30000, got %d", eventOne.PurchasedAmountCents)
	}
	if eventOne.RedeemedAmountCents != 20000 {
		t.Fatalf("expected event 1 redeemed=20000, got %d", eventOne.RedeemedAmountCents)
	}

	eventTwo, ok := perEvent[2]
	if !ok {
		t.Fatalf("expected event 2 bucket")
	}
	if eventTwo.PurchasedAmountCents != 5000 || eventTwo.RedeemedAmountCents != 0 {
		t.Fatalf("expected event 2 totals to be purchased=5000 redeemed=0, got purchased=%d redeemed=%d", eventTwo.PurchasedAmountCents, eventTwo.RedeemedAmountCents)
	}
}
