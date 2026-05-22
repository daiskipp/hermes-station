import postgres from "postgres";

function buildConnectionString(): string {
  if (process.env.DATABASE_URL) {
    return process.env.DATABASE_URL;
  }
  const user = process.env.POSTGRES_USER || "postgres";
  const password = process.env.POSTGRES_PASSWORD || "postgres";
  const db = process.env.POSTGRES_DB || "postgres";
  return `postgresql://${user}:${password}@postgres:5432/${db}`;
}

const sql = postgres(buildConnectionString(), {
  connect_timeout: 5,
  idle_timeout: 30,
  max: 5,
});

export default sql;
