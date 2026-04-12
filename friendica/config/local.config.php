<?php
/**
 * Friendica local configuration – atithi.social
 *
 * IMPORTANT – Docker users: this file is a REFERENCE TEMPLATE only.
 * The official Friendica Docker image auto-generates /var/www/html/config/local.config.php
 * from the environment variables defined in .env / docker-compose.yml.
 * You do NOT need to mount this file into the container unless you want
 * to apply overrides that are not covered by supported env vars.
 *
 * If you do want to use this file as a live override, add the following
 * volume mount to the `friendica` service in docker-compose.yml:
 *   - ./friendica/config/local.config.php:/var/www/html/config/local.config.php
 * (remove the :ro flag if you also want the container to be able to update it)
 *
 * Full reference of all available config keys:
 *   https://github.com/friendica/friendica/blob/stable/config/defaults.config.php
 */
 
return [
 
    // ── Database ──────────────────────────────────────────────────────────
    // Docker entrypoint populates these from MYSQL_* env vars automatically.
    'database' => [
        'hostname' => getenv('MYSQL_HOST')     ?: 'db',
        'username' => getenv('MYSQL_USER')     ?: '',
        'password' => getenv('MYSQL_PASSWORD') ?: '',
        'database' => getenv('MYSQL_DATABASE') ?: 'friendica',
        'charset'  => 'utf8mb4',
    ],
 
    // ── Core config ───────────────────────────────────────────────────────
    'config' => [
        'php_path'    => '/usr/local/bin/php',
        'sitename'    => getenv('FRIENDICA_SITENAME') ?: 'Atithi Social',
        'admin_email' => getenv('FRIENDICA_ADMIN_MAIL') ?: '',
    ],
 
    // ── System / instance ─────────────────────────────────────────────────
    'system' => [
        // Public URL – must match the SSL certificate; never change after federation starts
        'url'      => 'https://atithi.social',
        'timezone' => getenv('FRIENDICA_TZ')   ?: 'UTC',
        'language' => getenv('FRIENDICA_LANG') ?: 'en',
 
        // Trust forwarded headers from the Nginx reverse proxy on localhost
        'trusted_proxies'  => ['127.0.0.1', '::1'],
 
        // SSL is terminated at Nginx; Friendica itself runs plain HTTP internally
        // 0 = no forced redirect (Nginx handles it), 1 = force HTTPS
        'ssl_policy' => 0,
 
        // Worker process concurrency – tune to (vCPUs * 2) on your droplet
        // DigitalOcean basic droplets: start at 4 and increase if queues back up
        'worker_queues' => 4,
 
        // Maximum image size accepted (bytes) – 0 = unlimited
        'maximagesize' => 0,
 
        // Disable built-in proxy for remote images (Nginx handles caching)
        'proxy_disabled' => false,
    ],
 
    // ── Redis cache ───────────────────────────────────────────────────────
    // Docker entrypoint configures this from REDIS_HOST/PORT/PASSWORD env vars.
    // Listed here for documentation; only uncomment to override.
    //
    // 'redis' => [
    //     'host'     => getenv('REDIS_HOST')     ?: 'redis',
    //     'port'     => (int)(getenv('REDIS_PORT') ?: 6379),
    //     'password' => getenv('REDIS_PASSWORD') ?: null,
    //     'db'       => 0,
    // ],
    //
    // 'cache' => [
    //     'driver' => 'redis',
    // ],
    //
    // 'lock' => [
    //     'driver' => 'redis',
    // ],
 
    // ── Logging ───────────────────────────────────────────────────────────
    // 0 = CRITICAL, 1 = ERROR, 2 = WARNING, 3 = INFO, 4 = DEBUG (verbose)
    // Keep at 2 (WARNING) in production to avoid filling disk.
    'logger' => [
        'logfile'   => 'logs/friendica.log',
        'loglevel'  => 2,
        'debuglogs' => false,
    ],
 
];