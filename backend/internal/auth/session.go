package auth

type Session struct {
	Authenticated bool   `json:"authenticated"`
	UserID        int64  `json:"userId,omitempty"`
	Username      string `json:"username,omitempty"`
	IsAdmin       bool   `json:"isAdmin,omitempty"`
}

func AnonymousSession() Session {
	return Session{Authenticated: false}
}
