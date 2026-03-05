// This script runs on first MongoDB start to create application-level user.
// The root user is created via MONGO_INITDB_ROOT_USERNAME/PASSWORD env vars.
// This creates a restricted user for the application with minimum privileges.

const appUser = process.env.MONGO_APP_USER || "moltbot_app";
const appPass = process.env.MONGO_APP_PASS || "CHANGE_ME";
const appDb = process.env.MONGO_APP_DB || "moltbot";

db = db.getSiblingDB(appDb);

db.createUser({
  user: appUser,
  pwd: appPass,
  roles: [
    { role: "readWrite", db: appDb }
  ]
});

print("Application user created with readWrite access to " + appDb + " database only.");
