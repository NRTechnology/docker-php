# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-09-10

### Added

- Initial production-ready structure for the `docker-php` repository.
- Standardized PHP-FPM Docker image templates for:
  - PHP 7.4
  - PHP 8.3
  - PHP 8.4
  - PHP 8.5
- Standardized Docker image naming:
  - `local/php:7.4`
  - `local/php:8.3`
  - `local/php:8.4`
  - `local/php:8.5`
- PHP-FPM baseline configuration with:
  - Production-oriented PHP settings.
  - OPcache configuration.
  - Secure session cookie settings.
  - Error logging to container stderr.
  - Disabled `display_errors`.
  - Disabled `allow_url_include`.
  - `cgi.fix_pathinfo = 0`.
- Standardized PHP-FPM pool configuration using Unix sockets.
- Standardized Docker Compose template with:
  - `read_only: true`
  - `no-new-privileges:true`
  - tmpfs
  - CPU and memory limits
  - PID limits
  - file descriptor limits
  - read-only application source mount
  - separate writable runtime directories
  - PHP-FPM configuration mounted separately
  - `/run/php` socket directory
  - `/run/mysqld` read-only socket mount
- Standardized Nginx virtual host template.
- Nginx configuration with:
  - PHP-FPM Unix socket integration.
  - `try_files` handling.
  - Security headers.
  - Hidden-file protection.
  - Sensitive file extension protection.
  - PHP execution restrictions for writable directories.
- Standardized application directory structure under `/var/apps`.
- Standardized Docker application configuration under `/opt/docker-apps`.
- Framework-aware application generator supporting:
  - Laravel
  - CodeIgniter 4
  - Generic PHP application
- Application generator commands:
  - `./create-php-app.sh myapp 8.3 laravel`
  - `./create-php-app.sh myapp2 8.4 ci`
  - `./create-php-app.sh myapp3 8.5 generic`
  - `./create-php-app.sh legacy-app 7.4 generic`
- Automatic creation of application writable directories based on framework.
- Automatic generation of PHP-FPM pool configuration.
- Automatic generation of Docker Compose configuration.
- Automatic generation of Nginx virtual host configuration.
- Automatic Nginx configuration validation using `nginx -t`.
- Docker Compose configuration validation using `docker compose config`.
- Image build script for all supported PHP versions.
- Image test script for checking:
  - PHP version.
  - PHP modules.
  - PHP configuration.
  - PHP-FPM configuration.
- Requirement checking and installation script:
  - `scripts/check-requirements.sh`
- Automatic detection and installation of:
  - Nginx
  - Docker Engine
  - Docker Compose Plugin
  - MariaDB Server
  - MariaDB Client
- Docker installation using the official Docker APT repository for supported Ubuntu/Debian systems.
- Automatic service enablement and startup for:
  - Nginx
  - Docker
  - MariaDB
- Validation of:
  - Nginx configuration.
  - Docker daemon.
  - Docker Compose.
  - MariaDB service.
- Standardized production deployment documentation.
- Security and hardening guidance for PHP-FPM Docker deployments.

### Security

- Application source code is mounted read-only into PHP-FPM containers.
- Writable application data is separated from source code.
- Docker containers use `no-new-privileges`.
- Containers use a read-only root filesystem where practical.
- Runtime writable locations are explicitly mounted.
- PHP error display is disabled.
- PHP error logging is redirected to container stderr.
- `allow_url_include` is disabled.
- `cgi.fix_pathinfo` is disabled.
- PHP sessions use strict mode.
- PHP session cookies use `HttpOnly`.
- PHP session cookies are configured for HTTPS using `Secure`.
- Nginx blocks hidden files and sensitive file types.
- PHP execution in writable/upload areas is restricted.
- The project deliberately does not use `cap_drop: ALL` because of runtime compatibility considerations.

### Changed

- Standardized repository paths:
  - Repository: `/opt/docker-php`
  - Application Docker configurations: `/opt/docker-apps`
  - Application data/source: `/var/apps`
- Standardized Nginx-to-PHP-FPM communication through Unix sockets.
- Standardized PHP-to-MariaDB communication through TCP.
- Standardized timezone to `Asia/Jakarta`.
- Standardized PHP application container naming as `<application-name>-php`.
- Standardized per-application Docker bridge networks.

### Notes

- PHP 7.4 is retained for legacy application compatibility and should not be selected for new applications.
- `session.cookie_secure = 1` assumes the application is served over HTTPS.
- Redis extension versions included in the PHP image templates should be tested against the target application before production deployment.
- `mariadb-secure-installation` is intentionally not executed automatically by `scripts/check-requirements.sh` because it is an interactive security configuration step.
- The requirement installation script does not automatically modify:
  - Firewall rules.
  - MariaDB network binding.
  - Docker daemon configuration.
  - DNS settings.
  - Other production-specific network policies.
- Existing Docker installations are not automatically replaced when the `docker` command already exists. This avoids unexpectedly modifying an existing production Docker environment.

## [Unreleased]

### Planned

- Additional PHP versions when required and supported.
- Additional framework-specific templates.
- More automated security validation.
- Automated backup and restore helper scripts.
- Additional health checks for generated application environments.
- CI-based Docker image testing.
- Documentation improvements.
- Additional production deployment examples.

---

## Versioning

This project uses Semantic Versioning:

- **MAJOR** — incompatible changes to the deployment architecture or configuration.
- **MINOR** — backward-compatible features and improvements.
- **PATCH** — backward-compatible bug fixes and corrections.

### Release History

| Version | Release Date | Description |
|---|---|---|
| **1.0.0** | **2026-09-10** | Initial standardized production PHP-FPM Docker deployment release. |

[Unreleased]: https://github.com/NRTechnology/docker-php/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/NRTechnology/docker-php/releases/tag/v1.0.0