# Changelog

## [0.4.5](https://github.com/rmrighes-sonar/sonarqube-compose/compare/v0.4.4...v0.4.5) (2026-09-22)


### Bug Fixes

* **grafana:** add legendFormat to timeseries panels missing one ([f3895d9](https://github.com/rmrighes-sonar/sonarqube-compose/commit/f3895d9604b8afb55e13f789fa544a1a1b053d1a))

## [0.4.4](https://github.com/rmrighes-sonar/sonarqube-compose/compare/v0.4.3...v0.4.4) (2026-09-22)


### Bug Fixes

* **sonarqube:** enable performance monitoring so Web API/DB panels populate ([454a0ad](https://github.com/rmrighes-sonar/sonarqube-compose/commit/454a0ada554cc795d205525d4b8203675e69dd40))

## [0.4.3](https://github.com/rmrighes-sonar/sonarqube-compose/compare/v0.4.2...v0.4.3) (2026-09-22)


### Bug Fixes

* **grafana:** remove misleading sparkline on boolean status panels ([4197179](https://github.com/rmrighes-sonar/sonarqube-compose/commit/4197179a9886d68e64451fc1fcbc64c078a15540))

## [0.4.2](https://github.com/rmrighes-sonar/sonarqube-compose/compare/v0.4.1...v0.4.2) (2026-09-22)


### Bug Fixes

* **ci:** support a PAT for release-please to skip the bot-PR approval gate ([49752e5](https://github.com/rmrighes-sonar/sonarqube-compose/commit/49752e5c2e4b6b331c41a7b4721490bc43cb47ec))

## [0.4.1](https://github.com/rmrighes-sonar/sonarqube-compose/compare/v0.4.0...v0.4.1) (2026-09-22)


### Bug Fixes

* **ci:** enable GPG signature verification for Sonar Scanner CLI download ([6ce72e6](https://github.com/rmrighes-sonar/sonarqube-compose/commit/6ce72e6ba1ad4e53247281a9083ed138684af547))

## [0.4.0](https://github.com/rmrighes-sonar/sonarqube-compose/compare/v0.3.1...v0.4.0) (2026-09-22)


### Features

* add healthchecks for mcp/ngrok and surface reachability in Grafana ([be5726c](https://github.com/rmrighes-sonar/sonarqube-compose/commit/be5726cff6c7a6120f57581390a02259d81a8b47))

## [0.3.1](https://github.com/rmrighes-sonar/sonarqube-compose/compare/v0.3.0...v0.3.1) (2026-09-17)


### Bug Fixes

* **grafana:** clean up Usage dashboard clutter and fix trend panels ([#8](https://github.com/rmrighes-sonar/sonarqube-compose/issues/8)) ([ddbb509](https://github.com/rmrighes-sonar/sonarqube-compose/commit/ddbb5098095c442c8f5216c697d86aa502560015))

## [0.3.0](https://github.com/rmrighes-sonar/sonarqube-compose/compare/v0.2.0...v0.3.0) (2026-09-17)


### Features

* consume sonarqube-prometheus-exporter by name ([ab7c258](https://github.com/rmrighes-sonar/sonarqube-compose/commit/ab7c258dbbe5ca674151916056a9718a11a65d64))

## [0.2.0](https://github.com/rmrighes-sonar/sonarqube-compose/compare/v0.1.1...v0.2.0) (2026-09-16)


### Features

* add opt-in MCP server profile for AI agent integration ([#5](https://github.com/rmrighes-sonar/sonarqube-compose/issues/5)) ([7eebdbb](https://github.com/rmrighes-sonar/sonarqube-compose/commit/7eebdbb785334e076e17851852456eada57c3b22))

## [0.1.1](https://github.com/rmrighes-sonar/sonarqube-compose/compare/v0.1.0...v0.1.1) (2026-09-16)


### Bug Fixes

* set sonar.projectVersion from release-please's manifest ([#3](https://github.com/rmrighes-sonar/sonarqube-compose/issues/3)) ([2a11706](https://github.com/rmrighes-sonar/sonarqube-compose/commit/2a117069011f8e199b87130f66af97f7cb4a91e6))
