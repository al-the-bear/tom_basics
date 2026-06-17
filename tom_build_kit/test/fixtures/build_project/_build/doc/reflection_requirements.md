# Reflection Requirements

This document captures reflection usage and configuration requirements across the workspace,
with a focus on the _build tool entrypoints and their dependency chains.

## Summary

- Reflection usage is driven by tom_core_kernel and tom_core_server, which depend on tom_reflection.
- The _build tool entrypoints depend on tom_build_cli, which in turn depends on those core projects.
- The reflection builder is only required where tom_reflection is used (directly or via dependencies).

## Why the _build tools depend on tom_build_cli

The following tool entrypoints are thin wrappers that import tom_build_cli and delegate to its CLI functions:

- _build/bin/doc_scanner.dart imports package:tom_build_cli/cli_entry.dart
- _build/bin/docspecs.dart imports package:tom_build_cli/cli_entry.dart
- _build/bin/md2latex.dart imports package:tom_build_cli/cli_entry.dart
- _build/bin/md2pdf.dart imports package:tom_build_cli/cli_entry.dart
- _build/bin/ws_analyzer.dart imports package:tom_build_cli/cli_entry.dart
- _build/bin/ws_prepper.dart imports package:tom_build_cli/cli_entry.dart

| Tool entrypoint | Imported API | Why reflection is required | Evidence |
| --- | --- | --- | --- |
| _build/bin/doc_scanner.dart | tom_build_cli/cli_entry.dart | Transitive dependency on tom_core_kernel and tom_core_server (tom_reflection usage) | _build/bin/doc_scanner.dart, devops/tom_build_cli/pubspec.yaml, core/tom_core_kernel/lib/src/tombase/reflection/reflection.dart, core/tom_core_server/lib/src/d4rt_bridges/tom_core_server_bridges.dart |
| _build/bin/docspecs.dart | tom_build_cli/cli_entry.dart | Transitive dependency on tom_core_kernel and tom_core_server (tom_reflection usage) | _build/bin/docspecs.dart, devops/tom_build_cli/pubspec.yaml, core/tom_core_kernel/lib/src/tombase/reflection/reflection.dart, core/tom_core_server/lib/src/d4rt_bridges/tom_core_server_bridges.dart |
| _build/bin/md2latex.dart | tom_build_cli/cli_entry.dart | Transitive dependency on tom_core_kernel and tom_core_server (tom_reflection usage) | _build/bin/md2latex.dart, devops/tom_build_cli/pubspec.yaml, core/tom_core_kernel/lib/src/tombase/reflection/reflection.dart, core/tom_core_server/lib/src/d4rt_bridges/tom_core_server_bridges.dart |
| _build/bin/md2pdf.dart | tom_build_cli/cli_entry.dart | Transitive dependency on tom_core_kernel and tom_core_server (tom_reflection usage) | _build/bin/md2pdf.dart, devops/tom_build_cli/pubspec.yaml, core/tom_core_kernel/lib/src/tombase/reflection/reflection.dart, core/tom_core_server/lib/src/d4rt_bridges/tom_core_server_bridges.dart |
| _build/bin/ws_analyzer.dart | tom_build_cli/cli_entry.dart | Transitive dependency on tom_core_kernel and tom_core_server (tom_reflection usage) | _build/bin/ws_analyzer.dart, devops/tom_build_cli/pubspec.yaml, core/tom_core_kernel/lib/src/tombase/reflection/reflection.dart, core/tom_core_server/lib/src/d4rt_bridges/tom_core_server_bridges.dart |
| _build/bin/ws_prepper.dart | tom_build_cli/cli_entry.dart | Transitive dependency on tom_core_kernel and tom_core_server (tom_reflection usage) | _build/bin/ws_prepper.dart, devops/tom_build_cli/pubspec.yaml, core/tom_core_kernel/lib/src/tombase/reflection/reflection.dart, core/tom_core_server/lib/src/d4rt_bridges/tom_core_server_bridges.dart |

These entrypoints do not directly define reflection annotations. tom_build_cli itself has no @tomReflector/@tomReflection usages
in code (only a comment reference), but it depends on tom_core_kernel and tom_core_server, which use tom_reflection:

- Comment-only reference: devops/tom_build_cli/lib/src/dartscript/d4rt_globals.dart

- tom_core_kernel uses tom_reflection in core reflection APIs and bean locator services.
- tom_core_server uses tom_reflection mirrors in server-side bridge code.

As a result, reflection generation is required for the entrypoints above because they transitively load classes that
use tom_reflection when running those tools.

## Workspace project table

Columns:
- **tom_reflection dep**: tom_reflection present in pubspec dependencies/dev_dependencies/dependency_overrides
- **reflection builder**: build.yaml config includes tom_reflection_generator:reflection_generator
- **annotations**: source contains @tomReflector or @tomReflection

| Project path | Project name | tom_reflection dep | reflection builder | annotations |
| --- | --- | --- | --- | --- |
| _build | _build | No | Yes | No |
| _scripts | tom_scripts | No | No | No |
| ai_build/tom_ai | tom_ai | No | No | No |
| ai_build/tom_ai_build | tom_ai_build | No | No | No |
| ai_build/tom_codespec | tom_codespec | No | No | No |
| cloud/tom_provisioning | tom_provisioning | No | No | No |
| cloud/tom_provisioning_server | tom_provisioning_server | No | No | No |
| core/tom_core_flutter | tom_core_flutter | Yes | No | Yes (1) |
| core/tom_core_kernel | tom_core_kernel | Yes | Yes | Yes (31) |
| core/tom_core_server | tom_core_server | No | No | Yes (10) |
| dartscript/tom_dartscript_bridges | tom_dartscript_bridges | No | No | No |
| devops/tom_build | tom_build | Yes | Yes | No |
| devops/tom_build/fixture/workspaces/basic_test/core_lib | core_lib | No | No | No |
| devops/tom_build/fixture/workspaces/basic_test/my_cli | my_cli | No | No | No |
| devops/tom_build/fixture/workspaces/basic_test/my_server | my_server | No | No | No |
| devops/tom_build/fixture/workspaces/basic_test/utils_lib | utils_lib | No | No | No |
| devops/tom_build/test/tom/fixtures/tomplates | tomplates | No | No | No |
| devops/tom_build_cli | tom_build_cli | No | Yes | Yes (1) |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_config/app_c | app_c | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_config/lib_a | lib_a | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_config/lib_b | lib_b | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_order/core_lib | core_lib | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_order/main_app | main_app | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_order/service_lib | service_lib | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_order/utils_lib | utils_lib | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_features/project_with_assets | project_with_assets | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_features/project_with_build_runner | project_with_build_runner | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_features/project_with_docker | project_with_docker | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_features/project_with_examples | project_with_examples | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_features/project_with_reflection | project_with_reflection | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_features/project_with_tests | project_with_tests | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_features/publishable_project | publishable_project | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_folder_listings/project_with_folders | project_with_folders | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_local_index/project_with_local_index | project_with_local_index | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_local_index/project_with_null_overrides | project_with_null_overrides | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_merge_actions/project_no_overrides | project_no_overrides | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_merge_actions/project_with_action_override | project_with_action_override | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_merge_actions/project_with_cross_compile | project_with_cross_compile | No | No | No |
| devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_merge_actions/project_with_mode_override | project_with_mode_override | No | No | No |
| devops/tom_build_cli/test/fixtures/ws_prepper | test_package | No | No | No |
| devops/tom_deploy | tom_deploy | No | No | No |
| devops/tom_deploy_tools | tom_deploy_tools | No | No | No |
| sqm/tom_sqm_admin_client | tom_sqm_admin_client | No | No | No |
| sqm/tom_sqm_codespec | tom_sqm_codespec | No | No | No |
| sqm/tom_sqm_customer_client | tom_sqm_customer_client | No | No | No |
| sqm/tom_sqm_server | tom_sqm_server | No | No | No |
| uam/tom_uam_client | tom_uam_client | No | Yes | Yes (3) |
| uam/tom_uam_codespec | tom_uam_codespec | No | No | Yes (1) |
| uam/tom_uam_server | tom_uam_server | No | Yes | Yes (8) |
| vscode/tom_vscode_bridge | tom_vscode_bridge | No | No | No |
| vscode/tom_vscode_scripting_api | tom_vscode_scripting_api | No | No | No |
| xternal/named_semaphores | runtime_native_semaphores | No | No | No |
| xternal/tom_module_basics/tom_analyzer | tom_analyzer | No | No | No |
| xternal/tom_module_basics/tom_basics | tom_basics | No | No | Yes (1) |
| xternal/tom_module_basics/tom_basics_console | tom_basics_console | No | No | No |
| xternal/tom_module_basics/tom_basics_network | tom_basics_network | No | No | No |
| xternal/tom_module_basics/tom_version_builder | tom_version_builder | No | No | No |
| xternal/tom_module_communication/tom_chattools | tom_chattools | No | No | No |
| xternal/tom_module_crypto/tom_crypto | tom_crypto | No | No | No |
| xternal/tom_module_crypto/tom_tools | tom_tools | No | No | No |
| xternal/tom_module_d4rt/tom_d4rt | tom_d4rt | No | No | No |
| xternal/tom_module_d4rt/tom_d4rt_dcli | tom_d4rt_dcli | No | No | No |
| xternal/tom_module_d4rt/tom_d4rt_generator | tom_d4rt_generator | No | No | No |
| xternal/tom_module_d4rt/tom_d4rt_generator/example | d4rt_generator_example | No | No | No |
| xternal/tom_module_d4rt/tom_d4rt_generator/example/advanced_examples | advanced_examples | No | No | No |
| xternal/tom_module_d4rt/tom_d4rt_generator/example/explorative_examples | explorative_examples | No | No | No |
| xternal/tom_module_d4rt/tom_d4rt_generator/example/user_guide | user_guide_example | No | No | No |
| xternal/tom_module_d4rt/tom_d4rt_generator/example/user_reference | user_reference_example | No | No | No |
| xternal/tom_module_d4rt/tom_d4rt_generator/example/userbridge_override | userbridge_override_example | No | No | No |
| xternal/tom_module_d4rt/tom_d4rt_test | tom_d4rt_test | No | No | No |
| xternal/tom_module_distributed/tom_dist_ledger | tom_dist_ledger | No | No | No |
| xternal/tom_module_distributed/tom_dist_ledger_tool | tom_dist_ledger_tool | No | No | No |
| xternal/tom_module_distributed/tom_distributed_orchestration | tom_distributed_orchestration | No | No | No |
| xternal/tom_module_distributed/tom_distributed_orchestration_tool | tom_distributed_orchestration_tool | No | No | No |
| xternal/tom_module_distributed/tom_process_monitor | tom_process_monitor | No | No | No |
| xternal/tom_module_distributed/tom_process_monitor_tool | tom_process_monitor_tool | No | No | No |
| xternal/tom_module_reflection/tom_reflection | tom_reflection | No | Yes | No |
| xternal/tom_module_reflection/tom_reflection_generator | tom_reflection_generator | Yes | No | No |
| xternal/tom_module_reflection/tom_reflection_test | tom_reflection_test | Yes | Yes | No |
| zom_workspaces/zom_analyzer_test/zom_test_flutter | zom_test_flutter | No | No | No |
| zom_workspaces/zom_analyzer_test/zom_test_package | zom_test_package | No | No | No |
| zom_workspaces/zom_analyzer_test/zom_test_standalone | zom_test_standalone | No | No | No |

## Annotation locations (projects with @tomReflector/@tomReflection)

- core/tom_core_flutter
  - core/tom_core_flutter/lib/src/tomclient/security/authentication.dart
- core/tom_core_kernel
  - core/tom_core_kernel/test/reflection_test.dart
  - core/tom_core_kernel/test/observable_test.dart
  - core/tom_core_kernel/example/samples/shutdown_cleanup/02_advanced_shutdown_example.dart
  - core/tom_core_kernel/example/samples/observable/05_tom_map.dart
  - core/tom_core_kernel/example/samples/observable/04_tom_list.dart
  - core/tom_core_kernel/example/samples/observable/03_tom_class.dart
  - core/tom_core_kernel/example/samples/beanlocator/05_annotation_based_beans_example.dart
  - core/tom_core_kernel/example/samples/reflection/02_nested_objects_example.dart
  - core/tom_core_kernel/example/samples/reflection/05_tomclass_integration_example.dart
  - core/tom_core_kernel/example/samples/reflection/01_basic_reflection_example.dart
  - core/tom_core_kernel/example/samples/reflection/06_advanced_reflection_example.dart
  - core/tom_core_kernel/example/samples/reflection/04_datetime_types_example.dart
  - core/tom_core_kernel/example/samples/reflection/03_collections_example.dart
  - core/tom_core_kernel/example/observable/05_tom_map.dart
  - core/tom_core_kernel/example/observable/04_tom_list.dart
  - core/tom_core_kernel/example/observable/03_tom_class.dart
  - core/tom_core_kernel/example/beanlocator/02_bean_dependency_patterns_example.dart
  - core/tom_core_kernel/example/reflection/02_nested_objects_example.dart
  - core/tom_core_kernel/example/reflection/05_tomclass_integration_example.dart
  - core/tom_core_kernel/example/reflection/01_basic_reflection_example.dart
  - core/tom_core_kernel/example/reflection/06_advanced_reflection_example.dart
  - core/tom_core_kernel/example/reflection/04_datetime_types_example.dart
  - core/tom_core_kernel/example/reflection/03_collections_example.dart
  - core/tom_core_kernel/lib/src/tombase/settings/settings_client_authorization.dart
  - core/tom_core_kernel/lib/src/tombase/security/authentication_authorization.dart
  - core/tom_core_kernel/lib/src/tombase/observable/tom_observable.dart
  - core/tom_core_kernel/lib/src/tombase/observable/tom_observable_objects.dart
  - core/tom_core_kernel/lib/src/tombase/logging/remote_logserver.dart
  - core/tom_core_kernel/lib/src/tombase/logging/remote_logoutput.dart
  - core/tom_core_kernel/lib/src/tombase/beanlocator/bean_locator.dart
  - core/tom_core_kernel/lib/src/tombase/reflection/reflection.dart
- core/tom_core_server
  - core/tom_core_server/lib/src/tomserver/datasources/mariadb_datasource.dart
  - core/tom_core_server/lib/src/tomserver/datasources/queries.dart
  - core/tom_core_server/lib/src/tomserver/datasources/mariadb_sql_dialect.dart
  - core/tom_core_server/lib/src/tomserver/datasources/datasource_initialization.dart
  - core/tom_core_server/lib/src/tomserver/configuration/base_server_configuration.dart
  - core/tom_core_server/lib/src/tomserver/healthcheck/health_check.dart
  - core/tom_core_server/lib/src/tomserver/db_migration/mariadb_migration_adapter.dart
  - core/tom_core_server/lib/src/tomserver/object_persistence/mariadb_repository.dart
  - core/tom_core_server/lib/src/tomserver/object_persistence/crud_repository.dart
  - core/tom_core_server/lib/src/tomserver/authentication/authentication_server.dart
- devops/tom_build_cli
  - devops/tom_build_cli/lib/src/dartscript/d4rt_globals.dart
- uam/tom_uam_client
  - uam/tom_uam_client/lib/00_main.dart
  - uam/tom_uam_client/lib/uam/sample_app_state.dart
  - uam/tom_uam_client/lib/uam/sample_app_services.dart
- uam/tom_uam_codespec
  - uam/tom_uam_codespec/lib/src/printing_dtos.dart
- uam/tom_uam_server
  - uam/tom_uam_server/bin/ae_internal_services.dart
  - uam/tom_uam_server/bin/afa_authentication_server.dart
  - uam/tom_uam_server/bin/afd_exposed_services.dart
  - uam/tom_uam_server/bin/afc_log_server.dart
  - uam/tom_uam_server/bin/afb_settings_server.dart
  - uam/tom_uam_server/bin/aa_server_start.dart
  - uam/tom_uam_server/bin/src/uam/uam_persistence_model.dart
  - uam/tom_uam_server/bin/src/uam/uam_application_context.dart
- xternal/tom_module_basics/tom_basics
  - xternal/tom_module_basics/tom_basics/lib/src/runtime/platform_environment_runtime.dart

## Dependency graph (path dependencies only)

This graph is generated from path-based dependencies in pubspec.yaml files across the workspace.
Paths are listed as they appear in each pubspec.yaml (relative paths are preserved).

```mermaid
graph TD
  "_build" --> "../devops/tom_build_cli"
  "_build" --> "../devops/tom_deploy_tools"
  "_build" --> "../dartscript/tom_dartscript_bridges"
  "_build" --> "../xternal/tom_module_d4rt/tom_d4rt"
  "_build" --> "../xternal/tom_module_d4rt/tom_d4rt_dcli"
  "_build" --> "../xternal/tom_module_d4rt/tom_d4rt_generator"
  "_build" --> "../xternal/tom_module_reflection/tom_reflection_generator"
  "_build" --> "../xternal/tom_module_basics/tom_basics_network"
  "_build" --> "../vscode/tom_vscode_bridge"
  "_build" --> "../xternal/tom_module_distributed/tom_dist_ledger_tool"
  "_build" --> "../xternal/tom_module_distributed/tom_process_monitor_tool"
  "_build" --> "../xternal/tom_module_basics/tom_version_builder"
  "_build" --> "../xternal/named_semaphores"
  "_scripts" --> "../dartscript/tom_dartscript_bridges"
  "_scripts" --> "../vscode/tom_vscode_scripting_api"
  "_scripts" --> "../xternal/tom_module_d4rt/tom_d4rt"
  "core/tom_core_flutter" --> "../tom_core_kernel"
  "core/tom_core_flutter" --> "../../xternal/tom_module_d4rt/tom_d4rt"
  "core/tom_core_flutter" --> "../../xternal/tom_module_d4rt/tom_d4rt_generator"
  "core/tom_core_kernel" --> "../../devops/tom_build"
  "core/tom_core_kernel" --> "../../xternal/tom_module_d4rt/tom_d4rt"
  "core/tom_core_kernel" --> "../../xternal/tom_module_d4rt/tom_d4rt_generator"
  "core/tom_core_kernel" --> "../tom_core_server"
  "core/tom_core_server" --> "../tom_core_kernel"
  "core/tom_core_server" --> "../../xternal/tom_module_basics/tom_basics_console"
  "core/tom_core_server" --> "../../devops/tom_build"
  "core/tom_core_server" --> "../../xternal/tom_module_d4rt/tom_d4rt"
  "core/tom_core_server" --> "../../xternal/tom_module_d4rt/tom_d4rt_generator"
  "dartscript/tom_dartscript_bridges" --> "../../xternal/tom_module_d4rt/tom_d4rt"
  "dartscript/tom_dartscript_bridges" --> "../../xternal/tom_module_d4rt/tom_d4rt_dcli"
  "dartscript/tom_dartscript_bridges" --> "../../core/tom_core_kernel"
  "dartscript/tom_dartscript_bridges" --> "../../core/tom_core_server"
  "dartscript/tom_dartscript_bridges" --> "../../devops/tom_build"
  "dartscript/tom_dartscript_bridges" --> "../../vscode/tom_vscode_scripting_api"
  "dartscript/tom_dartscript_bridges" --> "../../xternal/tom_module_distributed/tom_dist_ledger"
  "dartscript/tom_dartscript_bridges" --> "../../xternal/tom_module_distributed/tom_process_monitor"
  "dartscript/tom_dartscript_bridges" --> "../../xternal/tom_module_basics/tom_basics_network"
  "dartscript/tom_dartscript_bridges" --> "../../xternal/tom_module_d4rt/tom_d4rt_generator"
  "dartscript/tom_dartscript_bridges" --> "../../xternal/tom_module_basics/tom_version_builder"
  "devops/tom_build" --> "../../xternal/tom_module_d4rt/tom_d4rt"
  "devops/tom_build" --> "../../core/tom_core_kernel"
  "devops/tom_build" --> "../../core/tom_core_server"
  "devops/tom_build" --> "../../xternal/tom_module_distributed/tom_dist_ledger"
  "devops/tom_build" --> "../../xternal/tom_module_distributed/tom_process_monitor"
  "devops/tom_build" --> "../../xternal/tom_module_d4rt/tom_d4rt_generator"
  "devops/tom_build" --> "../../xternal/tom_module_reflection/tom_reflection_generator"
  "devops/tom_build/fixture/workspaces/basic_test/my_cli" --> "../core_lib"
  "devops/tom_build/fixture/workspaces/basic_test/my_cli" --> "../utils_lib"
  "devops/tom_build/fixture/workspaces/basic_test/my_server" --> "../core_lib"
  "devops/tom_build/fixture/workspaces/basic_test/utils_lib" --> "../core_lib"
  "devops/tom_build_cli" --> "../tom_build"
  "devops/tom_build_cli" --> "../../xternal/tom_module_d4rt/tom_d4rt"
  "devops/tom_build_cli" --> "../../core/tom_core_kernel"
  "devops/tom_build_cli" --> "../../core/tom_core_server"
  "devops/tom_build_cli" --> "../../xternal/tom_module_distributed/tom_dist_ledger"
  "devops/tom_build_cli" --> "../../xternal/tom_module_distributed/tom_process_monitor"
  "devops/tom_build_cli" --> "../../dartscript/tom_dartscript_bridges"
  "devops/tom_build_cli" --> "../../xternal/tom_module_reflection/tom_reflection_generator"
  "devops/tom_build_cli" --> "../../xternal/tom_module_d4rt/tom_d4rt_generator"
  "devops/tom_build_cli" --> "../../xternal/tom_module_basics/tom_version_builder"
  "devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_config/app_c" --> "../lib_a"
  "devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_config/app_c" --> "../lib_b"
  "devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_config/lib_b" --> "../lib_a"
  "devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_order/main_app" --> "../service_lib"
  "devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_order/service_lib" --> "../core_lib"
  "devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_order/service_lib" --> "../utils_lib"
  "devops/tom_build_cli/test/fixtures/workspace_analyzer/ws_build_order/utils_lib" --> "../core_lib"
  "devops/tom_build_cli/test/fixtures/ws_prepper" --> "../tom_core"
  "devops/tom_build_cli/test/fixtures/ws_prepper" --> "../tom_shared"
  "uam/tom_uam_client" --> "../../core/tom_core_flutter"
  "uam/tom_uam_client" --> "../tom_uam_codespec"
  "uam/tom_uam_client" --> "../../devops/tom_build"
  "uam/tom_uam_codespec" --> "../../core/tom_core_kernel"
  "uam/tom_uam_server" --> "../../core/tom_core_kernel"
  "uam/tom_uam_server" --> "../tom_uam_codespec"
  "uam/tom_uam_server" --> "../../devops/tom_build"
  "vscode/tom_vscode_bridge" --> "../tom_vscode_scripting_api"
  "vscode/tom_vscode_bridge" --> "../../xternal/tom_module_d4rt/tom_d4rt"
  "vscode/tom_vscode_bridge" --> "../../dartscript/tom_dartscript_bridges"
  "vscode/tom_vscode_bridge" --> "../../xternal/tom_module_basics/tom_version_builder"
  "vscode/tom_vscode_bridge" --> "../../xternal/named_semaphores"
  "xternal/tom_module_crypto/tom_tools" --> "../tom_crypto"
  "xternal/tom_module_d4rt/tom_d4rt_dcli" --> "../tom_d4rt"
  "xternal/tom_module_d4rt/tom_d4rt_dcli" --> "../tom_d4rt_generator"
  "xternal/tom_module_d4rt/tom_d4rt_dcli" --> "../../named_semaphores"
  "xternal/tom_module_d4rt/tom_d4rt_generator/example" --> "../../tom_d4rt"
  "xternal/tom_module_d4rt/tom_d4rt_generator/example" --> ".."
  "xternal/tom_module_d4rt/tom_d4rt_generator/example/advanced_examples" --> "../../../tom_d4rt"
  "xternal/tom_module_d4rt/tom_d4rt_generator/example/advanced_examples" --> "../.."
  "xternal/tom_module_d4rt/tom_d4rt_generator/example/explorative_examples" --> "../../../tom_d4rt"
  "xternal/tom_module_d4rt/tom_d4rt_generator/example/explorative_examples" --> "../.."
  "xternal/tom_module_d4rt/tom_d4rt_generator/example/user_guide" --> "../../../tom_d4rt"
  "xternal/tom_module_d4rt/tom_d4rt_generator/example/user_guide" --> "../.."
  "xternal/tom_module_d4rt/tom_d4rt_generator/example/user_reference" --> "../../../tom_d4rt"
  "xternal/tom_module_d4rt/tom_d4rt_generator/example/user_reference" --> "../.."
  "xternal/tom_module_d4rt/tom_d4rt_generator/example/userbridge_override" --> "../../../tom_d4rt"
  "xternal/tom_module_d4rt/tom_d4rt_generator/example/userbridge_override" --> "../.."
  "xternal/tom_module_distributed/tom_dist_ledger" --> "../../tom_module_d4rt/tom_d4rt"
  "xternal/tom_module_distributed/tom_dist_ledger" --> "../../tom_module_basics/tom_basics_network"
  "xternal/tom_module_distributed/tom_dist_ledger" --> "../../tom_module_d4rt/tom_d4rt_generator"
  "xternal/tom_module_distributed/tom_dist_ledger_tool" --> "../tom_dist_ledger"
  "xternal/tom_module_distributed/tom_process_monitor" --> "../../tom_module_d4rt/tom_d4rt"
  "xternal/tom_module_distributed/tom_process_monitor" --> "../../tom_module_basics/tom_basics_network"
  "xternal/tom_module_distributed/tom_process_monitor" --> "../../tom_module_d4rt/tom_d4rt_generator"
  "xternal/tom_module_distributed/tom_process_monitor_tool" --> "../tom_process_monitor"
  "xternal/tom_module_reflection/tom_reflection" --> "../tom_reflection_generator"
```

## Prompt

This document was generated based on the following prompt:

TODO: create a document reflection_requirements.md in the _build/doc folder with this analysis.

TODO: Please check which of these project really have a build.yaml with reflection generator configured, provide a table of all projects in the workspace, which shows:

- has tom_reflection dependency in pubspec.yaml
- has tom_reflection builder configured in the build.yaml
- has annotations @tomReflection/@tomReflector
- create a dependency graph between the projects in the workspace
- especially explain why doc_scanner, docspecs, md2latex, md2pdf, ws_analyzer, ws_prepper depend on tom_build_cli (for which part) and if any of the classes used from tom_build_cli reflection is appearing in the imports or an reflection annotation is present.

Add the information to the reflection_requirements.md

TODO: add this exact prompt to the end of the document, saying: this document was generated based on the following prompt.
