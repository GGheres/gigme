package ticketing

// StatsRow represents stats row.
type StatsRow struct {
	OrderID     string
	EventID     int64
	EventTitle  string
	Status      string
	AmountCents int64
	ItemType    string
	ProductRef  string
	Quantity    int64
}

// StatsBucket represents stats bucket.
type StatsBucket struct {
	EventID                      int64
	EventTitle                   string
	PurchasedAmountCents         int64
	RedeemedAmountCents          int64
	TransferPurchasedAmountCents int64
	TransferRedeemedAmountCents  int64
	TicketTypeCounts             map[string]int64
	TransferDirectionCounts      map[string]int64
}

// NewStatsBucket creates stats bucket.
func NewStatsBucket(eventID int64, title string) StatsBucket {
	return StatsBucket{
		EventID:                 eventID,
		EventTitle:              title,
		TicketTypeCounts:        map[string]int64{"SINGLE": 0, "GROUP2": 0, "GROUP10": 0},
		TransferDirectionCounts: map[string]int64{"THERE": 0, "BACK": 0, "ROUNDTRIP": 0},
	}
}

// AggregateStats handles aggregate stats.
func AggregateStats(rows []StatsRow) (StatsBucket, map[int64]StatsBucket) {
	global := NewStatsBucket(0, "")
	perEvent := map[int64]StatsBucket{}
	for _, row := range rows {
		if row.EventID <= 0 {
			continue
		}
		bucket, ok := perEvent[row.EventID]
		if !ok {
			bucket = NewStatsBucket(row.EventID, row.EventTitle)
		}
		if bucket.EventTitle == "" && row.EventTitle != "" {
			bucket.EventTitle = row.EventTitle
		}

		if isPurchasedStatus(row.Status) {
			switch row.ItemType {
			case "TICKET":
				bucket.PurchasedAmountCents += row.AmountCents
				global.PurchasedAmountCents += row.AmountCents
				if _, ok := bucket.TicketTypeCounts[row.ProductRef]; ok {
					bucket.TicketTypeCounts[row.ProductRef] += row.Quantity
					global.TicketTypeCounts[row.ProductRef] += row.Quantity
				}
			case "TRANSFER":
				bucket.TransferPurchasedAmountCents += row.AmountCents
				global.TransferPurchasedAmountCents += row.AmountCents
				if _, ok := bucket.TransferDirectionCounts[row.ProductRef]; ok {
					bucket.TransferDirectionCounts[row.ProductRef] += row.Quantity
					global.TransferDirectionCounts[row.ProductRef] += row.Quantity
				}
			}
		}
		if row.Status == "REDEEMED" {
			switch row.ItemType {
			case "TICKET":
				bucket.RedeemedAmountCents += row.AmountCents
				global.RedeemedAmountCents += row.AmountCents
			case "TRANSFER":
				bucket.TransferRedeemedAmountCents += row.AmountCents
				global.TransferRedeemedAmountCents += row.AmountCents
			}
		}

		perEvent[row.EventID] = bucket
	}
	return global, perEvent
}

// isPurchasedStatus reports whether purchased status condition is met.
func isPurchasedStatus(status string) bool {
	switch status {
	case "PAID", "CONFIRMED", "REDEEMED":
		return true
	default:
		return false
	}
}
