const ENV_KEYS = {
  accountId: 'R2_ACCOUNT_ID',
  accessKeyId: 'R2_ACCESS_KEY_ID',
  secretAccessKey: 'R2_SECRET_ACCESS_KEY',
  bucket: 'R2_BUCKET',
};

export function loadConfig() {
  const cfg = {};
  const missing = [];
  for (const [key, env] of Object.entries(ENV_KEYS)) {
    cfg[key] = process.env[env];
    if (!cfg[key]) missing.push(env);
  }
  return { cfg, missing };
}
