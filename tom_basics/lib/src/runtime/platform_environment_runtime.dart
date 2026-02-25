import 'platform_neutral.dart';
import '../logging/logging.dart';

// =============================================================================
// Environment Configuration
// =============================================================================

/// Defines a runtime environment configuration.
///
/// Environments allow different bean implementations to be selected based
/// on the current runtime context (development, testing, production, etc.).
///
/// ## Environment Hierarchy
///
/// Environments can have parent environments, forming a hierarchy:
///
/// ```dart
/// const prodEnv = TomEnvironment("production");
/// const stagingEnv = TomEnvironment("staging", parent: prodEnv);
/// ```
///
/// ## Environment Initialization
///
/// Each environment can have an initializer function that runs when the
/// environment is activated:
///
/// ```dart
/// final devEnv = TomEnvironment(
///   "development",
///   isDevelopment: true,
///   initializer: (env) {
///     // Configure dev-specific settings
///   },
/// );
/// ```
class TomEnvironment {
  /// The parent environment in the hierarchy.
  final TomEnvironment? parent;

  /// The unique name identifying this environment.
  final String env;

  /// Optional initialization function called when environment is activated.
  final void Function(TomEnvironment)? initializer;

  /// Whether this environment is for testing.
  final bool isTest;

  /// Whether this environment is for development.
  final bool isDevelopment;

  /// Creates a new environment configuration.
  ///
  /// [env] Unique identifier for this environment.
  /// [parent] Optional parent environment for hierarchy.
  /// [initializer] Optional function to run when environment is activated.
  /// [isTest] Set to true for test environments.
  /// [isDevelopment] Set to true for development environments.
  const TomEnvironment(
    this.env, {
    this.parent,
    this.initializer,
    this.isTest = false,
    this.isDevelopment = false,
  });

  /// Runs the environment initializer if one is configured.
  void initialize() {
    if (initializer != null) {
      initializer!(this);
    }
  }

  @override
  String toString() {
    return "TomEnvironment $env Parent: ${parent ?? "no parent"} "
        "has initializer: ${initializer != null}";
  }
}

// =============================================================================
// Platform Configuration
// =============================================================================

/// Defines a target platform for bean selection.
///
/// Platforms allow different bean implementations based on the runtime
/// platform (iOS, Android, Web, etc.).
///
/// ## Platform-Specific Beans
///
/// ```dart
/// @tomReflector
/// @TomComponent(StorageService)
/// @platformIos
/// class IosStorageService implements StorageService { ... }
///
/// @tomReflector
/// @TomComponent(StorageService)
/// @platformAndroid
/// class AndroidStorageService implements StorageService { ... }
/// ```
class TomPlatform {
  /// Map of platform names to their initializer functions.
  static final Map<String, void Function(TomPlatform, TomEnvironment?)>
  _tomPlatformInitializers = {};

  /// The unique name identifying this platform.
  final String name;

  /// Creates a platform configuration.
  ///
  /// [name] Unique identifier for this platform.
  const TomPlatform(this.name);

  /// Registers an initializer function for this platform.
  ///
  /// The initializer is called when this platform is activated during
  /// [TomRuntime.initializePlatform].
  void setInitializer(void Function(TomPlatform, TomEnvironment?) initializer) {
    _tomPlatformInitializers[name] = initializer;
  }

  /// Runs the platform initializer if one is registered.
  ///
  /// [env] The current environment, passed to the initializer.
  void initializePlatform(TomEnvironment? env) {
    void Function(TomPlatform, TomEnvironment?)? initializer =
        _tomPlatformInitializers[name];
    if (initializer != null) {
      initializer(this, env);
    }
  }

  @override
  String toString() {
    return "TomPlatform: $name";
  }
}

// -----------------------------------------------------------------------------
// Platform Constants
// -----------------------------------------------------------------------------

/// Web platform constant.
const platformWeb = TomPlatform("web");

/// macOS platform constant.
const platformMacos = TomPlatform("macos");

/// Windows platform constant.
const platformWindows = TomPlatform("windows");

/// Android platform constant.
const platformAndroid = TomPlatform("android");

/// iOS platform constant.
const platformIos = TomPlatform("ios");

/// Linux platform constant.
const platformLinux = TomPlatform("linux");

/// Fuchsia platform constant.
const platformFuchsia = TomPlatform("fuchsia");

// -----------------------------------------------------------------------------
// Environment Constants
// -----------------------------------------------------------------------------

/// Default environment when none is specified.
const defaultTomEnvironment = TomEnvironment("default");

/// Sentinel value indicating no environment constraint.
const noTomEnvironment = TomEnvironment("none");

/// Sentinel value indicating no platform constraint.
const noTomPlatform = TomPlatform("none");

// =============================================================================
// Runtime Configuration
// =============================================================================

/// Central runtime configuration manager.
///
/// [TomRuntime] manages the global state for:
/// - Current and available environments
/// - Current and available platforms
/// - Environment hierarchy resolution
///
/// ## Initialization
///
/// ```dart
/// // Add environments
/// TomRuntime.addEnvironment(TomEnvironment("dev", isDevelopment: true));
/// TomRuntime.addEnvironment(TomEnvironment("prod"));
///
/// // Set current environment
/// TomRuntime.setCurrentEnvironment("dev");
///
/// // Initialize platform detection
/// TomRuntime.initializePlatform();
/// ```
///
/// ## Environment Hierarchy
///
/// Use [getEnvironmentHierarchy] to get the full chain of parent environments:
///
/// ```dart
/// final hierarchy = TomRuntime.getEnvironmentHierarchy();
/// // Returns [root, parent, current] in order
/// ```
class TomRuntime {
  /// Root environment (default fallback).
  static TomEnvironment _root = defaultTomEnvironment;

  /// List of all registered environments.
  static final List<TomEnvironment> _environments = List.empty(growable: true);

  /// List of all registered platforms.
  static final List<TomPlatform> _platforms = List.empty(growable: true);

  /// Currently active platform.
  static TomPlatform? _currentPlatform;

  /// Currently active environment.
  static TomEnvironment? _currentEnvironment;

  // ---------------------------------------------------------------------------
  // Diagnostic Methods
  // ---------------------------------------------------------------------------

  /// Returns a diagnostic report of the current runtime state.
  static String printReport() {
    return "TomRuntime: Platform ${_currentPlatform ?? "not set"} "
        "Root Environment $_root "
        "Current Environment ${_currentEnvironment ?? "not set"}";
  }

  // ---------------------------------------------------------------------------
  // Environment Management
  // ---------------------------------------------------------------------------

  /// Returns a copy of all registered environments.
  static List<TomEnvironment> getEnvironments() {
    return List.of(_environments);
  }

  /// Registers a new environment and returns it.
  ///
  /// [env] The environment to register.
  static TomEnvironment addEnvironment(TomEnvironment env) {
    _environments.add(env);
    return env;
  }

  /// Sets the root environment (ultimate fallback).
  static void setRootEnvironment(TomEnvironment env) {
    _root = env;
  }

  /// Sets the current environment by name.
  ///
  /// [name] The environment name to activate.
  /// [fallback] Fallback environment name if [name] not found.
  ///   Use "defaultRoot" to fall back to [defaultTomEnvironment].
  static void setCurrentEnvironment(
    String? name, [
    String fallback = "defaultRoot",
  ]) {
    // Try to find environment by name
    for (var env in _environments) {
      if (env.env == name) {
        _currentEnvironment = env;
        return;
      }
    }

    // Handle fallback to default root
    if (_currentEnvironment == null && fallback == "defaultRoot") {
      tomLog.info("Environment fallback to defaultRoot");
      _currentEnvironment = defaultTomEnvironment;
      return;
    }

    // Try named fallback
    if (_currentEnvironment == null && fallback.isNotEmpty) {
      tomLog.info("Environment fallback to $fallback");
      setCurrentEnvironment(fallback, "");
    }

    // Ultimate fallback to root
    tomLog.info("Environment fallback to root $_root");
    _currentEnvironment ??= _root;
  }

  /// Returns the current environment.
  ///
  /// Throws [Exception] if no environment has been initialized.
  static TomEnvironment getCurrentEnvironment() {
    if (_currentEnvironment == null) {
      throw Exception("environment has not been initialized");
    }
    return _currentEnvironment!;
  }

  /// Returns the environment hierarchy from root to current.
  ///
  /// The returned list is ordered from root (first) to current (last).
  static List<TomEnvironment> getEnvironmentHierarchy() {
    List<TomEnvironment> environments = [];
    TomEnvironment env = TomRuntime.getCurrentEnvironment();
    environments.add(env);

    while (env.parent != null) {
      env = env.parent!;
      environments.add(env);
    }

    return List.from(environments.reversed);
  }

  /// Returns the root environment.
  static TomEnvironment getRoot() {
    return _root;
  }

  // ---------------------------------------------------------------------------
  // Platform Management
  // ---------------------------------------------------------------------------

  /// Registers a platform and returns it.
  static TomPlatform addPlatform(TomPlatform platform) {
    _platforms.add(platform);
    return platform;
  }

  /// Returns a copy of all registered platforms.
  static List<TomPlatform> getPlatforms() {
    return List.of(_platforms);
  }

  /// Returns the current platform, or null if not set.
  static TomPlatform? getCurrentPlatform() {
    return _currentPlatform;
  }

  /// Sets the current platform.
  static void setCurrentPlatform(TomPlatform platform) {
    _currentPlatform = platform;
  }

  /// Detects and initializes the current platform.
  ///
  /// Registers all known platforms, detects the current platform using
  /// [TomPlatformUtils], and runs the platform's initializer.
  static void initializePlatform() {
    _registerKnownPlatforms();
    _detectCurrentPlatform();
    TomRuntime.getCurrentPlatform()?.initializePlatform(_currentEnvironment);
  }

  /// Registers all known platform constants.
  static void _registerKnownPlatforms() {
    TomRuntime.addPlatform(platformWeb);
    TomRuntime.addPlatform(platformMacos);
    TomRuntime.addPlatform(platformWindows);
    TomRuntime.addPlatform(platformLinux);
    TomRuntime.addPlatform(platformAndroid);
    TomRuntime.addPlatform(platformIos);
    TomRuntime.addPlatform(platformFuchsia);
  }

  /// Detects and sets the current platform based on runtime checks.
  static void _detectCurrentPlatform() {
    if (TomPlatformUtils.current.isAndroid()) {
      TomRuntime.setCurrentPlatform(platformAndroid);
    } else if (TomPlatformUtils.current.isIos()) {
      TomRuntime.setCurrentPlatform(platformIos);
    } else if (TomPlatformUtils.current.isFuchsia()) {
      TomRuntime.setCurrentPlatform(platformFuchsia);
    } else if (TomPlatformUtils.current.isLinux()) {
      TomRuntime.setCurrentPlatform(platformLinux);
    } else if (TomPlatformUtils.current.isWindows()) {
      TomRuntime.setCurrentPlatform(platformWindows);
    } else if (TomPlatformUtils.current.isMacOs()) {
      TomRuntime.setCurrentPlatform(platformMacos);
    } else {
      TomRuntime.setCurrentPlatform(platformWeb);
    }
  }
}