#// Scenario 0:
#//
#// Setup initialize


#//----------------------------------------------------------------------------
#//
#// Setup
#//
#//----------------------------------------------------------------------------


#// 1
#//
#// Setup initialize
POST /setup/_initialize
{
	"name":"admin",
    "email":"admin@mail.com",
    "password":"PASSword_123",
    "language":"zh-CN"
}
# assert: (200, {acknowledged: true}),