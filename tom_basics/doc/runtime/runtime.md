# Tom Runtime System

The Tom Runtime System provides platform-neutral abstractions and runtime configuration for cross-platform Dart and Flutter applications. It enables code to run seamlessly across web, mobile, and desktop environments while managing environment and platform-specific behavior for dependency injection.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Core Components](#core-components)
  - [TomPlatformUtils](#tomplatformutils)
  - [TomEnvironment](#tomenvironment)
  - [TomPlatform](#tomplatform)
  - [TomRuntime](#tomruntime)
- [Initialization Sequence](#initialization-sequence)
- [Environment Configuration](#environment-configuration)
- [Platform Configuration](#platform-configuration)
- [Integration with Bean Context](#integration-with-bean-context)
- [Best Practices](#best-practices)
- [See Also](#see-also)

## Overview

The runtime module solves the challenge of writing platform-agnostic code by providing:

- **Platform Detection** - Determine the current execution environment
- **Console Output** - Unified logging and output across platforms
- **HTTP Client Factory** - Platform-appropriate HTTP client creation
- **Environment Variables** - Cross-platform configuration management
- **Environment Configuration** - Runtime environments (dev, test, prod) with hierarchy support
- **Platform Configuration** - Target platforms (iOS, Android, Web, etc.) for bean selection

The module consists of two main files:

1. **`lib/src/runtime/platform_neutral.dart`**: Platform abstraction classes (`TomPlatformUtils`, `TomFallbackPlatformUtils`)
2. **`lib/src/runtime/platform_environment_runtime.dart`**: Runtime configuration (`TomEnvironment`, `TomPlatform`, `TomRuntime`)

The module lives in **`tom_basics`**, and `tom_core_kernel` re-exports it through
its barrel — so the code below compiles against either
`package:tom_basics/tom_basics.dart` or
`package:tom_core_kernel/tom_core_kernel.dart`. Several examples wire the runtime
up to the bean locator, reflection and logging, which are kernel-level concerns;
those need the kernel import.

## Quick Start

The runtime system must be initialized in a specific sequence before the bean context can be used. Here's the typical initialization pattern used in production applications:

### 1. Set Environment Variables

Before any initialization, configure the environment variables that control which environment will be selected:

```dart
void main(List<String> args) async {
  // Set environment variables (e.g., from command line, config files, etc.)
  TomPlatformUtils.envVars["env"] = "dev";
  TomPlatformUtils.envVars["useRemoteLogging"] = "false";
  
  // Continue with initialization
  await MyApplication.main(args);
}
```

### 2. Define Environments in a Separate File

Create a runtime definition file that defines your environment hierarchy:

```dart
// runtime_definition.dart

const environmentProd = TomEnvironment(
  'prod',
  initializer: initializeProd,
); // Root environment

const environmentInt = TomEnvironment(
  'int',
  parent: environmentProd,
  isTest: true,
  initializer: initializeInt,
);

const environmentDev = TomEnvironment(
  'dev',
  parent: environmentProd,
  isDevelopment: true,
  isTest: true,
  initializer: initializeDev,
);
```

### 3. Create the initializeRuntime Function

The `initializeRuntime()` function sets up the complete runtime state:

```dart
void initializeRuntime() {
  // 1. Register all environments
  TomRuntime.addEnvironment(environmentProd);
  TomRuntime.addEnvironment(environmentInt);
  TomRuntime.addEnvironment(environmentDev);

  // 2. Set root environment (ultimate fallback)
  TomRuntime.setRootEnvironment(environmentProd);

  // 3. Set current environment from envVars (with fallback)
  TomRuntime.setCurrentEnvironment(
    TomPlatformUtils.current.getTomEnvVars()["env"], 
    "prod", // fallback if env var not set
  );

  // 4. Run the environment initializer
  TomRuntime.getCurrentEnvironment().initialize();

  // 5. Initialize platform detection
  TomRuntime.initializePlatform();

  // 6. Log the current state
  tomLog.info(TomRuntime.printReport());
}
```

### 4. Application Main Sequence

The complete initialization sequence in your application:

```dart
class MyApplication {
  static Future<int> main(List<String> args) async {
    // 1. Set platform utilities (MUST be first)
    TomPlatformUtils.setCurrentPlatform(clientPlatformUtils); // or standalonePlatformUtils
    
    // 2. Initialize reflection (if using reflection)
    initializeReflection();
    
    // 3. Initialize runtime (environments + platform)
    initializeRuntime();
    
    // 4. Initialize bean context (AFTER runtime is ready)
    initializeBeanContext();
    
    // 5. Start application
    runApp(Application());
    return 0;
  }
}
```

## Core Components

### TomPlatformUtils

The main abstract class that defines the platform utilities contract. Set this first during application startup.

```dart
// Set the platform implementation at application start
TomPlatformUtils.setCurrentPlatform(MyPlatformUtils());

// Access environment variables
TomPlatformUtils.envVars["myKey"] = "myValue";

// Get the current platform implementation
final platform = TomPlatformUtils.current;
```

| Method | Description |
|--------|-------------|
| `isDesktop()` | Returns `true` if running on Windows, macOS, or Linux |
| `isMobile()` | Returns `true` if running on Android or iOS |
| `isWeb()` | Returns `true` if running in a web browser |
| `isWindows()` | Returns `true` if running on Windows |
| `isLinux()` | Returns `true` if running on Linux |
| `isMacOs()` | Returns `true` if running on macOS |
| `isFuchsia()` | Returns `true` if running on Fuchsia OS |
| `isAndroid()` | Returns `true` if running on Android |
| `isIos()` | Returns `true` if running on iOS |
| `out(String s)` | Outputs a message to the console |
| `outError(String s)` | Outputs an error message to the console |
| `httpClient()` | Creates a platform-appropriate HTTP client |
| `getTomEnvVars()` | Returns environment variables map |
| `getBrowserLocation()` | Returns current browser URL (web only) |
| `getIsolateName()` | Returns the name of the current isolate |

| Static Member | Description |
|---------------|-------------|
| `TomPlatformUtils.current` | The current platform utilities implementation |
| `TomPlatformUtils.envVars` | Mutable map for environment variables |
| `TomPlatformUtils.setCurrentPlatform(impl)` | Sets the current implementation |

### TomEnvironment

Environments define runtime configurations for different deployment contexts. They support hierarchy (parent environments) and initialization functions.

```dart
// Define environments with a hierarchy
const prodEnv = TomEnvironment('production', initializer: initProd);
const devEnv = TomEnvironment(
  'development', 
  parent: prodEnv,
  isDevelopment: true,
  initializer: initDev,
);
```

| Property | Type | Description |
|----------|------|-------------|
| `env` | `String` | Unique name identifying this environment |
| `parent` | `TomEnvironment?` | Optional parent environment for hierarchy |
| `isTest` | `bool` | Whether this is a test environment |
| `isDevelopment` | `bool` | Whether this is a development environment |
| `initializer` | `void Function(TomEnvironment)?` | Function called when `initialize()` is called |

| Method | Description |
|--------|-------------|
| `initialize()` | Runs the initializer function if one is configured |

### TomPlatform

Platforms represent target runtime environments. They are used for platform-specific bean selection via the `@TomPlatform` annotation.

```dart
// Built-in platform constants
platformWeb      // Web browsers
platformMacos    // macOS desktop
platformWindows  // Windows desktop
platformLinux    // Linux desktop
platformAndroid  // Android devices
platformIos      // iOS devices
platformFuchsia  // Fuchsia OS
```

```dart
// Register a platform initializer
platformAndroid.setInitializer((platform, env) {
  // Initialize Android-specific resources
});
```

### TomRuntime

Central manager for runtime state. Manages the global state for environments and platforms.

| Method | Description |
|--------|-------------|
| `addEnvironment(env)` | Registers a new environment |
| `setRootEnvironment(env)` | Sets the root (ultimate fallback) environment |
| `setCurrentEnvironment(name, [fallback])` | Sets current environment by name with optional fallback |
| `getCurrentEnvironment()` | Returns the current environment |
| `getEnvironmentHierarchy()` | Returns environments from root to current |
| `addPlatform(platform)` | Registers a platform |
| `setCurrentPlatform(platform)` | Sets the current platform |
| `getCurrentPlatform()` | Returns the current platform |
| `initializePlatform()` | Auto-detects and initializes the current platform |
| `printReport()` | Returns a diagnostic report of runtime state |

## Initialization Sequence

The initialization sequence is critical for the runtime and bean context to work correctly. Here is the complete order:

```
┌─────────────────────────────────────────────────────────────────┐
│ 1. Set environment variables (TomPlatformUtils.envVars)         │
│    ↓                                                            │
│ 2. Set platform utilities (TomPlatformUtils.setCurrentPlatform) │
│    ↓                                                            │
│ 3. Initialize reflection (initializeReflection)               │
│    ↓                                                            │
│ 4. Initialize runtime (initializeRuntime)                       │
│    ├─ Add environments (TomRuntime.addEnvironment)              │
│    ├─ Set root environment (TomRuntime.setRootEnvironment)      │
│    ├─ Set current environment (TomRuntime.setCurrentEnvironment)│
│    ├─ Call initializer (getCurrentEnvironment().initialize())   │
│    └─ Initialize platform (TomRuntime.initializePlatform)       │
│    ↓                                                            │
│ 5. Initialize bean context (initializeBeanContext)              │
│    ↓                                                            │
│ 6. Application is ready                                         │
└─────────────────────────────────────────────────────────────────┘
```

### Why This Order Matters

1. **Environment variables first**: The `env` variable determines which environment to select
2. **Platform utilities before runtime**: `TomRuntime.initializePlatform()` uses `TomPlatformUtils.current` to detect the platform
3. **Reflection before runtime**: Environment initializers may use reflection
4. **Runtime before bean context**: The bean context uses `TomRuntime.getCurrentEnvironment()` and `TomRuntime.getCurrentPlatform()` to select beans

## Environment Configuration

### Environment Hierarchy

Environments can form a hierarchy for configuration inheritance:

```dart
const baseEnv = TomEnvironment('base');
const devEnv = TomEnvironment('dev', parent: baseEnv, isDevelopment: true);
const localDevEnv = TomEnvironment('local-dev', parent: devEnv);

// Get hierarchy (root to current)
TomRuntime.setCurrentEnvironment('local-dev');
final hierarchy = TomRuntime.getEnvironmentHierarchy();
// Returns: [baseEnv, devEnv, localDevEnv]
```

### Environment Initializers

Initializers are functions that configure environment-specific settings:

```dart
void initializeDev(TomEnvironment env) {
  // Set log levels for development
  tomLog.setLogLevel(TomLogLevel.development);
  
  // Configure log levels per module
  tomLog.addNameLevel("TomBean", TomLogLevel.still);
  tomLog.addNameLevel("TomReflectionInfo", TomLogLevel.still);
  
  // Set remote API endpoints
  TomClientRemoteContext.setCurrent(
    TomClientRemoteContext(Uri.parse("http://localhost:9080/")),
  );
}

void initializeProd(TomEnvironment env) {
  tomLog.setLogLevel(TomLogLevel.production);
  
  TomClientRemoteContext.setCurrent(
    TomClientRemoteContext(Uri.parse("https://api.myapp.com/")),
  );
}
```

### Environment Constants

| Constant | Description |
|----------|-------------|
| `defaultTomEnvironment` | Default environment ("default") when none is specified |
| `noTomEnvironment` | Sentinel value indicating no environment constraint |
| `noTomPlatform` | Sentinel value indicating no platform constraint |

## Platform Configuration

### Platform Initialization

Platforms can have initializers that run when the platform is activated:

```dart
// Register custom initializer
platformAndroid.setInitializer((platform, env) {
  // Initialize Android-specific resources
});

// This is called by TomRuntime.initializePlatform()
```

### Platform Detection

`TomRuntime.initializePlatform()` automatically detects the current platform using `TomPlatformUtils`:

```dart
// After initializePlatform() is called:
final platform = TomRuntime.getCurrentPlatform();
print('Running on: ${platform?.name}'); // e.g., "macos", "android", "web"
```

## Integration with Bean Context

The runtime system is designed to work with the bean context for dependency injection. When `initializeBeanContext()` is called, it uses the current runtime state to select the appropriate bean implementations.

### Platform-Specific Beans

```dart
@tomReflector
@TomComponent(StorageService)
@platformIos
class IosStorageService implements StorageService { ... }

@tomReflector
@TomComponent(StorageService)
@platformAndroid
class AndroidStorageService implements StorageService { ... }

@tomReflector
@TomComponent(StorageService)
class DefaultStorageService implements StorageService { ... }
```

### Environment-Specific Beans

```dart
@tomReflector
@TomComponent(LoggingService)
@TomEnvironment("dev", isDevelopment: true)
class DevLoggingService implements LoggingService { ... }

@tomReflector
@TomComponent(LoggingService)
class ProductionLoggingService implements LoggingService { ... }
```

### Bean Resolution Priority

When `TomBean<T>.get()` is called, beans are selected with this priority:

1. **Exact match**: Both environment AND platform match
2. **Platform match**: Platform matches, no environment constraint
3. **Environment match**: Environment matches, no platform constraint
4. **Default**: No environment or platform constraints

## Best Practices

### 1. Define Environments as Constants

Use `const` for environment definitions to enable compile-time checking:

```dart
const environmentProd = TomEnvironment('prod', initializer: initProd);
const environmentDev = TomEnvironment('dev', parent: environmentProd, isDevelopment: true);
```

### 2. Use Environment Variables for Environment Selection

Don't hardcode the environment; use environment variables:

```dart
// ❌ Avoid
TomRuntime.setCurrentEnvironment("dev");

// ✅ Prefer
TomRuntime.setCurrentEnvironment(
  TomPlatformUtils.current.getTomEnvVars()["env"],
  "prod", // fallback
);
```

### 3. Create a Centralized initializeRuntime Function

Keep all runtime initialization in one place for clarity:

```dart
// runtime_definition.dart
void initializeRuntime() {
  TomRuntime.addEnvironment(environmentProd);
  TomRuntime.addEnvironment(environmentDev);
  TomRuntime.setRootEnvironment(environmentProd);
  TomRuntime.setCurrentEnvironment(
    TomPlatformUtils.current.getTomEnvVars()["env"],
    "prod",
  );
  TomRuntime.getCurrentEnvironment().initialize();
  TomRuntime.initializePlatform();
  tomLog.info(TomRuntime.printReport());
}
```

### 4. Use Separate Files for Environment Initialization

Keep environment-specific logic in separate files for maintainability:

```
lib/
├── main_dev.dart           # Sets envVars["env"] = "dev"
├── main_prod.dart          # Sets envVars["env"] = "prod"
├── runtime_definition.dart # Defines environments and initializeRuntime()
└── environment_init.dart   # Contains initializeDev(), initializeProd(), etc.
```

### 5. Handle Worker Isolates

When spawning worker isolates, pass the environment and platform:

```dart
class MyWorkerContext extends TomWorkerContext {
  MyWorkerContext(
    TomEnvironment tomEnvironment,
    TomPlatform tomPlatform,
    List<String> args,
    String namePrefix,
  ) : super(tomEnvironment, tomPlatform, args, namePrefix);

  @override
  Future<bool> initializeIsolate() async {
    TomPlatformUtils.setCurrentPlatform(myPlatformUtils);
    initializeReflection();
    initializeRuntime();
    // ... continue initialization
    return true;
  }
}
```

## File Structure

```
lib/src/runtime/
├── platform_neutral.dart              # Platform abstraction classes
└── platform_environment_runtime.dart  # Environment, Platform, Runtime classes

doc/runtime/
└── runtime.md                         # This documentation file
```

---

## Dependencies

This module has no internal Tom dependencies. It is a foundational module used by:

- **Bean Locator Module**: For environment and platform-specific bean selection
- **Logging Module**: For platform-aware logging
- **HTTP Connection Module**: For platform-specific HTTP client creation
