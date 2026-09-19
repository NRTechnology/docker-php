**\*\*# Changelog\*\***

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog]\\(https\\://keepachangelog.com/en/1.1.0/),

and this project follows [Semantic Versioning]\\(https\\://semver.org/).

**\*\*## [1.1.0] - 2026-09-18\*\***

**\*\*### Latest Updates (2026-09-19)\*\***

- Added database preflight before creating deployment resources.
- Added verification that MySQL/MariaDB root can log in without a password.
- Added detection of existing application databases before deployment.
- Added detection of existing database users across all `Host` entries.
- Deployment now stops on database/user conflicts before creating the Docker network, application directories, or Composer resources.
- Existing database and database user are not modified or deleted automatically.
- Docker network creation remains per application and stops if the requested network already exists.
- Laravel `vendor` dependencies are separated into the writable `/var/apps/<application-name>/data/vendor` directory.
- Laravel runtime storage is separated into dedicated writable directories for `storage/app`, `storage/framework`, `storage/logs`, and `bootstrap/cache`.
- Laravel Composer binary is prepared outside the PHP-FPM runtime image and mounted read-only.
- Composer dependency installation is documented using the `www-data` user.
- Laravel public storage symlink handling is standardized.
- Nginx PHP-FPM `SCRIPT_FILENAME` uses the container filesystem path `/var/www/html/...` instead of the host filesystem path.
- Added cleanup guidance for failed or partial application deployments.

**\*\*### Added\*\***

\\- Added support for PHP 8.2.

\\- Standardized supported PHP versions:

  - PHP 7.4

  - PHP 8.2

  - PHP 8.3

  - PHP 8.4

  - PHP 8.5

\\- Standardized PHP-FPM Docker image naming:

  - \\`local/php:7.4\\`

  - \\`local/php:8.2\\`

  - \\`local/php:8.3\\`

  - \\`local/php:8.4\\`

  - \\`local/php:8.5\\`

\\- Added framework-aware application generation for:

  - Laravel

  - CodeIgniter 4

  - Generic PHP application

\\- Added domain name parameter to the application generator.

\\- Added automatic generation of Nginx virtual host configuration based on the application domain.

\\- Added automatic creation of application directories:

  - \\`/opt/docker-apps/\\\<application-name>\\`

  - \\`/var/apps/\\\<application-name>\\`

\\- Added automatic creation of:

  - application source directory

  - writable runtime directories

  - application log directory

  - application backup directory

  - PHP-FPM pool configuration

  - Docker Compose configuration

  - Nginx virtual host configuration

**\*\*### Database\*\***

\\- Standardized **\*\*\\\*\\\*MariaDB as the default database platform\\\*\\\*\*\*** for production deployments.

\\- Retained compatibility with **\*\*\\\*\\\*MySQL\\\*\\\*\*\***.

\\- Added automatic database client detection:

  - \\`mariadb\\` is preferred when available.

  - \\`mysql\\` is used when the MariaDB client is not available.

\\- Added automatic database creation by \\`create-php-app.sh\\`.

\\- Added automatic database username creation.

\\- Added automatic secure database password generation.

\\- Added automatic database user privilege assignment limited to the application database.

\\- Added automatic database credentials file generation:

  - \\`/opt/docker-apps/\\\<application-name>/db-credentials.env\\`

\\- Database credentials file permissions are restricted to:

  - owner: \\`root\\`

  - permission: \\`0600\\`

\\- Added automatic restriction of the database user's allowed host based on the actual Docker network subnet.

\\- Docker network information is detected dynamically instead of using a hard-coded IP range.

\\- Application database configuration uses:

  - \\`DB\\\_CONNECTION=mysql\\`

  - \\`DB\\\_HOST=\\\<docker-gateway>\\`

  - \\`DB\\\_PORT=3306\\`

\\- \\`DB\\\_CONNECTION=mysql\\` is retained because the Laravel database driver name is \\`mysql\\` for both MySQL and MariaDB.

**\*\*### Requirement Installation\*\***

\\- Added standardized requirement checking and installation through:

  \\`scripts/check-requirements.sh\\`

\\- Added automatic detection and installation support for:

  - Nginx

  - Docker Engine

  - Docker Compose Plugin

  - MariaDB Server

  - MariaDB Client

\\- MariaDB is treated as the standard database server for a new deployment.

\\- Added validation of:

  - Nginx installation

  - Docker installation

  - Docker daemon

  - Docker Compose

  - MariaDB service

  - MariaDB client

\\- Added automatic service enablement and startup for required services.

\\- Docker installation uses the official Docker APT repository where supported.

\\- Existing Docker installations are not automatically replaced.

**\*\*### Docker\*\***

\\- Added standardized per-application Docker bridge networks.

\\- Application network names follow:

  \\`\\\<application-name>-network\\`

\\- Docker network configuration remains based on:

  \\`driver: bridge\\`

\\- The application generator creates the Docker network before Docker Compose deployment.

\\- Docker subnet and gateway are detected dynamically after network creation.

\\- PHP-FPM containers use per-application Docker networks.

\\- PHP-FPM containers use:

  - \\`read\\\_only: true\\`

  - \\`no-new-privileges\\\:true\\`

  - tmpfs for temporary runtime data

  - CPU limits

  - memory limits

  - PID limits

  - file descriptor limits

\\- Application source code is mounted read-only.

\\- Writable application directories are mounted separately.

\\- PHP-FPM configuration is mounted separately as read-only.

\\- PHP-FPM Unix socket directory is mounted separately.

**\*\*### PHP-FPM\*\***

\\- Standardized PHP-FPM pool configuration for generated applications.

\\- PHP-FPM communicates with Nginx using Unix sockets.

\\- Socket naming convention:

  \\`/run/php/\\\<application-name>.sock\\`

\\- Standardized socket permissions:

  - owner: \\`www-data\\`

  - group: \\`www-data\\`

  - mode: \\`0660\\`

\\- Standardized PHP-FPM process management:

  - dynamic process manager

  - configurable worker limits

  - worker recycling using \\`pm.max\\\_requests\\`

  - request termination timeout

  - slow request logging

  - worker output capture

**\*\*### Framework Templates\*\***

**\*\*#### Laravel\*\***

\\- Laravel document root:

  \\`/var/apps/\\\<application-name>/htdocs/public\\`

\\- Writable Laravel directories:

  - \\`/var/apps/\\\<application-name>/data/  - \\`/var/apps/\\\<application-name>/data/storage-app\\`

  - \\`/var/apps/\\\<application-name>/data/storage-framework\\`

  - \\`/var/apps/\\\<application-name>/data/storage-logs\\`

  - \\`/var/apps/\\\<application-name>/data/bootstrap-cache\\`

\\- Container mount points:

  - \\`/var/www/html/storage/app\\`

  - \\`/var/www/html/storage/framework\\`

  - \\`/var/www/html/storage/logs\\`

  - \\`/var/www/html/bootstrap/cache\\`

\\- Laravel application source code is mounted read-only.

\\- Laravel \\`vendor\\` dependencies are stored separately from the application source:

  \\`/var/apps/\\\<application-name>/data/vendor\\`

\\- The \\`vendor\\` directory is mounted read-write to:

  \\`/var/www/html/vendor\\`

\\- Composer is provided separately and is not included in the PHP-FPM runtime image.

\\- Composer is mounted read-only into the container.

\\- PHP execution is blocked inside Laravel writable directories.

**\*\*#### CodeIgniter 4\*\***

\\- CodeIgniter 4 document root:

  \\`/var/apps/\\\<application-name>/htdocs/public\\`

\\- CI4 writable directory:

  \\`/var/apps/\\\<application-name>/data/writable\\`

\\- Standard writable subdirectories:

  - \\`cache\\`

  - \\`logs\\`

  - \\`session\\`

  - \\`uploads\\`

\\- PHP execution is blocked inside the writable directory.

**\*\*#### Generic PHP\*\***

\\- Generic PHP document root:

  \\`/var/apps/\\\<application-name>/htdocs\\`

\\- Generic writable directory:

  \\`/var/apps/\\\<application-name>/data/writable\\`

\\- Standard writable subdirectories:

  - \\`cache\\`

  - \\`logs\\`

  - \\`session\\`

  - \\`uploads\\`

\\- PHP execution is blocked inside the writable data directory.

**\*\*### Nginx\*\***

\\- Added framework-aware Nginx document roots.

\\- Standardized PHP-FPM Unix socket integration.

\\- Added \\`try\\\_files\\` handling for application routing.

\\- Added security headers.

\\- Added hidden-file protection.

\\- Added protection against access to sensitive files.

\\- Protected file extensions include:

  - \\`.env\\`

  - \\`.ini\\`

  - \\`.log\\`

  - \\`.sql\\`

  - \\`.bak\\`

  - \\`.backup\\`

  - \\`.old\\`

  - \\`.orig\\`

  - \\`.save\\`

  - \\`.swp\\`

\\- Added PHP execution restrictions for writable application directories.

\\- Added automatic Nginx configuration validation using:

  \\`nginx -t\\`

\\- Added automatic Nginx site enablement through:

  \\`/etc/nginx/sites-enabled\\`

**\*\*### Application Generator\*\***

\\- Updated application generator usage to:

  \\`./create-php-app.sh \\\<app-name> \\\<php-version> \\\<framework> \\\<domain-name>\\`

\\- Supported framework values:

  - \\`laravel\\`

  - \\`ci\\`

  - \\`generic\\`

\\- Supported PHP versions:

  - \\`7.4\\`

  - \\`8.2\\`

  - \\`8.3\\`

  - \\`8.4\\`

  - \\`8.5\\`

\\- Example commands:

  \\`./create-php-app.sh myapp 8.2 laravel myapp.example.go.id\\`

  \\`./create-php-app.sh myapp2 8.4 ci myapp2.example.go.id\\`

  \\`./create-php-app.sh myapp3 8.5 generic myapp3.example.go.id\\`

  \\`./create-php-app.sh legacy-app 7.4 generic legacy.example.go.id\\`

\\- Added validation for:

  - application name

  - domain name

  - PHP version

  - framework

  - required Docker components

  - PHP image availability

  - existing application targets

  - database root passwordless login

  - existing database

  - existing database user across all Host entries

  - Docker network availability

\\- Added automatic Docker Compose configuration validation using:

  \\`docker compose config\\`

\\- The application generator does not automatically execute:

  \\`docker compose up -d\\`

  This allows the administrator to review the generated configuration before starting the application.

**\*\*### Security\*\***

\\- Application source code is mounted read-only into PHP-FPM containers.

\\- Writable application data is separated from application source code.

\\- Containers use \\`no-new-privileges\\`.

\\- Containers use a read-only root filesystem where practical.

\\- Temporary files use dedicated tmpfs storage.

\\- Runtime writable locations are explicitly mounted.

\\- PHP \\`display\\\_errors\\` is disabled.

\\- PHP errors are logged to container stderr.

\\- \\`allow\\\_url\\\_include\\` is disabled.

\\- \\`cgi.fix\\\_pathinfo\\` is disabled.

\\- PHP sessions use strict mode.

\\- PHP session cookies use \\`HttpOnly\\`.

\\- PHP session cookies are configured with \\`Secure\\`.

\\- Nginx blocks hidden files.

\\- Nginx blocks access to sensitive configuration and backup files.

\\- Nginx blocks PHP execution in writable/upload directories.

\\- Database credentials are stored outside the application source tree.

\\- Database credential files use permission \\`0600\\`.

\\- Database users are restricted to the application's database.

\\- Database user host restrictions are generated from the actual Docker subnet.

\\- The project deliberately does not use:

  \\`cap\\\_drop: ALL\\`

  because of runtime compatibility considerations observed in production environments.

**\*\*### Changed\*\***

\\- Changed the project database standard from generic MySQL/MariaDB support to:

  **\*\*\\\*\\\*MariaDB as the standard database platform, with MySQL compatibility retained.\\\*\\\*\*\***

\\- Changed supported PHP versions from:

  \\`7.4 | 8.3 | 8.4 | 8.5\\`

  to:

  \\`7.4 | 8.2 | 8.3 | 8.4 | 8.5\\`

\\- Changed the application generator to automatically create:

  - database

  - database user

  - database password

  - database credentials file

\\- Changed database host restriction from a fixed Docker network assumption to dynamic detection based on the actual Docker subnet.

\\- Standardized PHP-to-database communication through TCP.

\\- Standardized Nginx-to-PHP-FPM communication through Unix sockets.

\\- Standardized application container naming:

  \\`\\\<application-name>-php\\`

\\- Standardized Docker network naming:

  \\`\\\<application-name>-network\\`

\\- Standardized timezone to:

  \\`Asia/Jakarta\\`

\\- Standardized repository paths:

  - Repository: \\`/opt/docker-php\\`

  - Application Docker configuration: \\`/opt/docker-apps\\`

  - Application source/data: \\`/var/apps\\`

**\*\*### Removed\*\***

\\- Removed the requirement for \\`/run/mysqld\\` socket mounting between the PHP-FPM container and host database.

\\- Database communication now uses TCP through the Docker network gateway.

\\- Removed hard-coded Docker database host assumptions.

**\*\*### Fixed\*\***

\\- Fixed database password generation under Bash \\`set -o pipefail\\`.

\\- Password generation no longer relies on a pipeline that may fail because of \\`SIGPIPE\\` from \\`head\\`.

\\- Database passwords are now generated using:

  - \\`openssl rand -hex\\`

  - or \\`/dev/urandom\\` as fallback.

\\- Improved validation of generated database passwords.

\\- Improved validation of Docker network information.

**\*\*### Notes\*\***

\\- MariaDB is the recommended and standardized database platform for new deployments.

\\- MySQL remains supported for environments where MySQL is already deployed or required by the application.

\\- The application generator automatically uses the available database client.

\\- The database server itself is not automatically migrated between MariaDB and MySQL.

\\- Existing production MySQL installations should not be replaced automatically.

\\- Database root credentials are not modified automatically by the application generator.

\\- Database root accounts should remain restricted to trusted/local administration.

\\- \\`scripts/check-requirements.sh\\` should not automatically overwrite an existing production database configuration.

\\- \\`mariadb-secure-installation\\` remains an interactive security hardening step and is not executed automatically.

\\- The requirement installation process does not automatically modify:

  - firewall rules

  - database network binding

  - Docker daemon configuration

  - DNS configuration

  - external reverse proxy configuration

  - TLS certificates

  - application-specific configuration

\\- PHP 7.4 is retained only for legacy application compatibility and should not be selected for new applications.

\\- PHP 8.2 is supported for applications whose dependency requirements are compatible with PHP 8.2.

\\- PHP 8.3, 8.4, and 8.5 are available for applications requiring newer PHP runtimes.

\\- The selected PHP version must be compatible with the application's dependency lock file.

\\- Composer is intentionally not included in the PHP-FPM runtime image.

\\- Application dependencies should be installed separately from the production PHP-FPM runtime container.

\\- \\`session.cookie\\\_secure = 1\\` assumes that the application is served through HTTPS.

\\- Redis extension compatibility should be tested against the target application before production deployment.

\\- The generated Docker network uses \\`driver: bridge\\`.

\\- Docker Compose may report a warning when the application network was created by the generator rather than by Compose itself. The network remains intentionally managed as a standard bridge network by the generator.

**\*\*## [1.0.0] - 2026-09-10\*\***

**\*\*### Added\*\***

\\- Initial production-ready structure for the \\`docker-php\\` repository.

\\- Standardized PHP-FPM Docker image templates.

\\- Standardized Nginx configuration.

\\- Standardized Docker Compose configuration.

\\- Standardized application directory structure.

\\- Framework-aware application generator.

\\- Initial Laravel, CodeIgniter 4, and Generic PHP support.

\\- Initial Docker and Nginx validation.

\\- Initial production security hardening guidance.

**\*\*## Versioning\*\***

This project uses Semantic Versioning:

\\- **\*\*\\\*\\\*MAJOR\\\*\\\*\*\*** — incompatible changes to the deployment architecture or configuration.

\\- **\*\*\\\*\\\*MINOR\\\*\\\*\*\*** — backward-compatible features and improvements.

\\- **\*\*\\\*\\\*PATCH\\\*\\\*\*\*** — backward-compatible bug fixes and corrections.

**\*\*### Release History\*\***

\\| Version | Release Date | Description |

\\|---|---|---|

\\| **\*\*\\\*\\\*1.1.0\\\*\\\*\*\*** | **\*\*\\\*\\\*2026-09-18\\\*\\\*\*\*** | Added PHP 8.2 support, standardized MariaDB as the database platform while retaining MySQL compatibility, automatic database/user/password creation, dynamic Docker subnet-based database access restriction, dedicated Laravel writable runtime mounts, external Composer preparation, and improvements to the application generator. |

\\| **\*\*\\\*\\\*1.0.0\\\*\\\*\*\*** | **\*\*\\\*\\\*2026-09-10\\\*\\\*\*\*** | Initial standardized production PHP-FPM Docker deployment release. |

[Unreleased]: https\\://github.com/NRTechnology/docker-php/compare/v1.1.0...HEAD

[1.1.0]: https\\://github.com/NRTechnology/docker-php/releases/tag/v1.1.0

[1.0.0]: https\\://github.com/NRTechnology/docker-php/releases/tag/v1.0.0
