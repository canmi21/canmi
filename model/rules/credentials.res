/**
 * The platform a credential belongs to, the foundation being the default and never written, and a
 * key local development holds apart from production's marked `Development`.
 */
type platform =
  | Foundation
  | Development
  | Test
  | Production
  | Organization(string)

/** One credential by its variable, the words it is made of and whether its subject is a vendor. */
type t = {
  variable: string,
  subject: string,
  tied: bool,
  platform: platform,
  purpose: string,
}

/** A credential tied to the vendor `subject`, which its variable names first. */
let vendor = (variable, subject, platform, purpose) => {
  variable,
  subject,
  tied: true,
  platform,
  purpose,
}

/** A credential with no tie to its vendor, `subject` being the component it belongs to. */
let neutral = (variable, subject, platform, purpose) => {
  variable,
  subject,
  tied: false,
  platform,
  purpose,
}

/** The words a name may not carry in the foundation, since the foundation is the default. */
let platformWords = ["DEVELOPMENT", "TEST", "PRODUCTION"]

/** The names GitHub or the runner supplies, which no file of ours holds. */
let supplied = ["GITHUB_TOKEN"]

/** Every credential the repositories use, secrets.json keys and workflow secrets alike. */
let table = [
  vendor("CLOUDFLARE_ACCOUNT_ID", "CLOUDFLARE", Foundation, "ACCOUNT_ID"),
  vendor("CLOUDFLARE_TOKEN_MANAGER", "CLOUDFLARE", Foundation, "TOKEN_MANAGER"),
  vendor("CLOUDFLARE_CONTROL_TUNNEL", "CLOUDFLARE", Foundation, "CONTROL_TUNNEL"),
  vendor("CLOUDFLARE_CANMI_TOKEN_MANAGER", "CLOUDFLARE", Organization("CANMI"), "TOKEN_MANAGER"),
  vendor("CLOUDFLARE_TEST_TOKEN_MANAGER", "CLOUDFLARE", Test, "TOKEN_MANAGER"),
  vendor("CLOUDFLARE_TEST_CONTROL_TUNNEL", "CLOUDFLARE", Test, "CONTROL_TUNNEL"),
  vendor("CLOUDFLARE_TEST_CONTROL_DEPLOY", "CLOUDFLARE", Test, "CONTROL_DEPLOY"),
  vendor("CLOUDFLARE_CONTROL_DEPLOY", "CLOUDFLARE", Foundation, "CONTROL_DEPLOY"),
  vendor("CLOUDFLARE_TEST_CONTROL_TOKEN", "CLOUDFLARE", Test, "CONTROL_TOKEN"),
  vendor("CLOUDFLARE_DRIVER_API_TOKEN", "CLOUDFLARE", Foundation, "DRIVER_API_TOKEN"),
  vendor("CLOUDFLARE_DRIVER_ACCOUNT_ID", "CLOUDFLARE", Foundation, "DRIVER_ACCOUNT_ID"),
  vendor("TAILSCALE_OAUTH_CLIENT_ID", "TAILSCALE", Foundation, "OAUTH_CLIENT_ID"),
  vendor("TAILSCALE_OAUTH_CLIENT_SECRET", "TAILSCALE", Foundation, "OAUTH_CLIENT_SECRET"),
  vendor("DOCKERHUB_TOKEN", "DOCKERHUB", Foundation, "TOKEN"),
  neutral("CONTROL_OPERATOR", "CONTROL", Foundation, "OPERATOR"),
  neutral("CONTROL_SEALING_KEY", "CONTROL", Foundation, "SEALING_KEY"),
  neutral("CONTROL_HEALTH", "CONTROL", Foundation, "HEALTH"),
  neutral("CONTROL_ORGANIZATION_MONOFLAKE", "CONTROL", Foundation, "ORGANIZATION_MONOFLAKE"),
  neutral("CONTROL_TEST_OPERATOR", "CONTROL", Test, "OPERATOR"),
  neutral("CONTROL_TEST_SEALING_KEY", "CONTROL", Test, "SEALING_KEY"),
  neutral("CONTROL_TEST_ORGANIZATION_SIDEQUESTS", "CONTROL", Test, "ORGANIZATION_SIDEQUESTS"),
  neutral("CONTROL_PRODUCTION_OPERATOR", "CONTROL", Production, "OPERATOR"),
  neutral("CONTROL_PRODUCTION_SEALING_KEY", "CONTROL", Production, "SEALING_KEY"),
  neutral("CONTROL_PRODUCTION_ORGANIZATION_CANMI", "CONTROL", Production, "ORGANIZATION_CANMI"),
  neutral("CONTROL_PRODUCTION_DEPLOY", "CONTROL", Production, "DEPLOY"),
  neutral("DRIVER_TEST_SIGNING_KEY", "DRIVER", Test, "SIGNING_KEY"),
  neutral("NIX_SIGNING_KEY", "NIX", Foundation, "SIGNING_KEY"),
  neutral("NIX_TEST_SIGNING_KEY", "NIX", Test, "SIGNING_KEY"),
  neutral("POINTER_SIGNING_KEY", "POINTER", Foundation, "SIGNING_KEY"),
  neutral("POINTER_TEST_SIGNING_KEY", "POINTER", Test, "SIGNING_KEY"),
  neutral("SYSTEMS_ENDPOINT", "SYSTEMS", Foundation, "ENDPOINT"),
  neutral("SYSTEMS_WRITE_KEY_ID", "SYSTEMS", Foundation, "WRITE_KEY_ID"),
  neutral("SYSTEMS_WRITE_SECRET", "SYSTEMS", Foundation, "WRITE_SECRET"),
  neutral("SYSTEMS_READ_KEY_ID", "SYSTEMS", Foundation, "READ_KEY_ID"),
  neutral("SYSTEMS_READ_SECRET", "SYSTEMS", Foundation, "READ_SECRET"),
  neutral("SYSTEMS_TEST_ENDPOINT", "SYSTEMS", Test, "ENDPOINT"),
  neutral("SYSTEMS_TEST_WRITE_KEY_ID", "SYSTEMS", Test, "WRITE_KEY_ID"),
  neutral("SYSTEMS_TEST_WRITE_SECRET", "SYSTEMS", Test, "WRITE_SECRET"),
  neutral("SYSTEMS_CANMI_ENDPOINT", "SYSTEMS", Organization("CANMI"), "ENDPOINT"),
  neutral("SYSTEMS_CANMI_WRITE_KEY_ID", "SYSTEMS", Organization("CANMI"), "WRITE_KEY_ID"),
  neutral("SYSTEMS_CANMI_WRITE_SECRET", "SYSTEMS", Organization("CANMI"), "WRITE_SECRET"),
  neutral("RUNNER_TOKEN", "RUNNER", Foundation, "TOKEN"),
  neutral("UPGRADE", "UPGRADE", Foundation, ""),
  neutral("BINDING", "BINDING", Foundation, ""),
  // A platform's salt master, from which deploy derives each organization's salt, b8f35.
  neutral("SALT_MASTER", "SALT", Foundation, "MASTER"),
  neutral("SALT_TEST_MASTER", "SALT", Test, "MASTER"),
  // The console's sign-in, WorkOS's staging key, in monoflake/console.
  vendor("WORKOS_API_KEY", "WORKOS", Foundation, "API_KEY"),
  // The console's sealing keys, one an environment reads as SEALING_KEY, by the author's word.
  neutral("CONSOLE_PRODUCTION_SEALING_KEY", "CONSOLE", Production, "SEALING_KEY"),
  neutral("CONSOLE_DEVELOPMENT_SEALING_KEY", "CONSOLE", Development, "SEALING_KEY"),
  // WorkOS's production environment, which the deployed console signs in through.
  vendor("WORKOS_PRODUCTION_API_KEY", "WORKOS", Production, "API_KEY"),
  // The console's Cloudflare OAuth client, which a person links their Cloudflare account through.
  vendor(
    "CLOUDFLARE_PRODUCTION_OAUTH_CLIENT_SECRET",
    "CLOUDFLARE",
    Production,
    "OAUTH_CLIENT_SECRET",
  ),
  // The photo behind an organization's sign-in card, Unsplash's access key, in monoflake/console.
  vendor("UNSPLASH_ACCESS_KEY", "UNSPLASH", Foundation, "ACCESS_KEY"),
  // The console vault's identity at Oracle, which may only use the one HSM key, RFC 3knhu.
  vendor("ORACLE_TENANCY", "ORACLE", Foundation, "TENANCY"),
  vendor("ORACLE_USER", "ORACLE", Foundation, "USER"),
  vendor("ORACLE_KEY", "ORACLE", Foundation, "KEY"),
  vendor("ORACLE_FINGERPRINT", "ORACLE", Foundation, "FINGERPRINT"),
  vendor("ORACLE_PRIVATE_KEY", "ORACLE", Foundation, "PRIVATE_KEY"),
  vendor("ORACLE_CRYPTO_ENDPOINT", "ORACLE", Foundation, "CRYPTO_ENDPOINT"),
  vendor("ORACLE_MANAGEMENT_ENDPOINT", "ORACLE", Foundation, "MANAGEMENT_ENDPOINT"),
  vendor("ORACLE_REGION", "ORACLE", Foundation, "REGION"),
  // The console vault's keys, each environment's read as the purpose alone, RFC 3knhu.
  neutral("VAULT_PRODUCTION_TOKEN_KEY", "VAULT", Production, "TOKEN_KEY"),
  neutral("VAULT_DEVELOPMENT_TOKEN_KEY", "VAULT", Development, "TOKEN_KEY"),
  neutral("VAULT_DEVELOPMENT_LOCAL_MASTER", "VAULT", Development, "LOCAL_MASTER"),
]

/** Names a secrets file or GitHub holds, beside each one's name after rotation, docs/naming.md. */
let planned = [
  ("NIX_SIGNING_KEY_TEST", "NIX_TEST_SIGNING_KEY"),
  ("POINTER_SIGNING_KEY_TEST", "POINTER_TEST_SIGNING_KEY"),
  ("CONTROL_TEST_CLOUDFLARE_TOKEN", "CLOUDFLARE_TEST_CONTROL_TOKEN"),
  ("TEST_DRIVER_SIGNING_KEY", "DRIVER_TEST_SIGNING_KEY"),
  ("DRIVER_API_TOKEN", "CLOUDFLARE_DRIVER_API_TOKEN"),
  ("DRIVER_ACCOUNT_ID", "CLOUDFLARE_DRIVER_ACCOUNT_ID"),
]

let words = variable => variable->String.split("_")->Array.filter(word => word != "")

/** A variable's display form, the name in its vendor's dashboard. */
let display = variable =>
  words(variable)
  ->Array.map(word =>
    word->String.slice(~start=0, ~end=1) ++ word->String.slice(~start=1)->String.toLowerCase
  )
  ->Array.join(" ")

/** A variable's short form, where a secret becomes a file. */
let short = variable => words(variable)->Array.map(String.toLowerCase)->Array.join("-")

/** The word a platform adds to a name, none for the foundation. */
let platformWord = platform =>
  switch platform {
  | Foundation => []
  | Development => ["DEVELOPMENT"]
  | Test => ["TEST"]
  | Production => ["PRODUCTION"]
  | Organization(word) => [word]
  }

/** The variable the order subject, platform, purpose gives an entry. */
let ordered = entry =>
  Array.flat([[entry.subject], platformWord(entry.platform), words(entry.purpose)])->Array.join("_")
