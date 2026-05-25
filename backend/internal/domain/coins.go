package domain

type CoinSlot struct {
	Slot   string `json:"slot"`
	Ticker string `json:"ticker"`
	Name   string `json:"name"`
	Role   string `json:"role"`
}

func DefaultSlots() []CoinSlot {
	return []CoinSlot{
		{Slot: "parent", Ticker: "BLC", Name: "Blakecoin", Role: "parent"},
		{Slot: "mm", Ticker: "PHO", Name: "Photon", Role: "aux"},
		{Slot: "mm1", Ticker: "BBTC", Name: "BlakeBitcoin", Role: "aux"},
		{Slot: "mm3", Ticker: "ELT", Name: "Electron", Role: "aux"},
		{Slot: "mm4", Ticker: "UMO", Name: "Universalmolecule", Role: "aux"},
		{Slot: "mm5", Ticker: "LIT", Name: "Lithium", Role: "aux"},
	}
}
