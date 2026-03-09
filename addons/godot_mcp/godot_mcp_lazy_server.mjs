import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const EXPECTED_PACKAGE_VERSION = process.env.GODOT_MCP_PACKAGE_VERSION ?? '2.16.0';
const DEFAULT_GODOT_PORT = 6550;
const __dirname = path.dirname(fileURLToPath(import.meta.url));

function readJson(jsonPath) {
  return JSON.parse(readFileSync(jsonPath, 'utf8'));
}

function parsePort(value) {
  if (!value) {
    return undefined;
  }

  const parsed = Number.parseInt(value, 10);
  if (Number.isNaN(parsed) || parsed < 1 || parsed > 65535) {
    return undefined;
  }

  return parsed;
}

function getNpxCacheRoot() {
  if (process.env.GODOT_MCP_NPX_ROOT) {
    return process.env.GODOT_MCP_NPX_ROOT;
  }

  if (!process.env.LOCALAPPDATA) {
    throw new Error('LOCALAPPDATA is not set, cannot locate npx cache for godot-mcp');
  }

  return path.join(process.env.LOCALAPPDATA, 'npm-cache', '_npx');
}

function getExplicitPackageRoot() {
  const explicitRoot = process.env.GODOT_MCP_PACKAGE_ROOT;
  if (!explicitRoot) {
    return null;
  }

  const packageJsonPath = path.join(explicitRoot, 'package.json');
  if (!existsSync(packageJsonPath)) {
    throw new Error(`GODOT_MCP_PACKAGE_ROOT does not contain package.json: ${explicitRoot}`);
  }

  return {
    root: explicitRoot,
    version: readJson(packageJsonPath).version ?? 'unknown',
    mtimeMs: statSync(packageJsonPath).mtimeMs,
  };
}

function findPackageCandidates() {
  const explicit = getExplicitPackageRoot();
  if (explicit) {
    return [explicit];
  }

  const npxRoot = getNpxCacheRoot();
  if (!existsSync(npxRoot)) {
    throw new Error(`npx cache root not found: ${npxRoot}`);
  }

  const candidates = [];
  for (const entry of readdirSync(npxRoot, { withFileTypes: true })) {
    if (!entry.isDirectory()) {
      continue;
    }

    const packageRoot = path.join(
      npxRoot,
      entry.name,
      'node_modules',
      '@satelliteoflove',
      'godot-mcp',
    );
    const packageJsonPath = path.join(packageRoot, 'package.json');
    if (!existsSync(packageJsonPath)) {
      continue;
    }

    const packageJson = readJson(packageJsonPath);
    candidates.push({
      root: packageRoot,
      version: packageJson.version ?? 'unknown',
      mtimeMs: statSync(packageJsonPath).mtimeMs,
    });
  }

  return candidates;
}

function resolvePackageRoot() {
  const candidates = findPackageCandidates();
  if (candidates.length === 0) {
    throw new Error('No cached @satelliteoflove/godot-mcp package was found');
  }

  const exactMatches = candidates
    .filter((candidate) => candidate.version === EXPECTED_PACKAGE_VERSION)
    .sort((left, right) => right.mtimeMs - left.mtimeMs);
  if (exactMatches.length > 0) {
    return exactMatches[0];
  }

  return candidates.sort((left, right) => right.mtimeMs - left.mtimeMs)[0];
}

function toModuleUrl(modulePath) {
  return pathToFileURL(modulePath).href;
}

const resolvedPackage = resolvePackageRoot();
const packageRoot = resolvedPackage.root;
const nodeModulesRoot = path.resolve(packageRoot, '..', '..');
const sdkRoot = path.join(nodeModulesRoot, '@modelcontextprotocol', 'sdk', 'dist', 'esm');

const [
  { Server },
  { StdioServerTransport },
  sdkTypes,
  { registry },
  { registerAllTools },
  { registerAllResources },
  { GodotConnection },
  { GodotCommandError },
  { setMcpServer, logger },
  { getServerVersion },
  { getTargetHost, getConnectionStrategy },
] = await Promise.all([
  import(toModuleUrl(path.join(sdkRoot, 'server', 'index.js'))),
  import(toModuleUrl(path.join(sdkRoot, 'server', 'stdio.js'))),
  import(toModuleUrl(path.join(sdkRoot, 'types.js'))),
  import(toModuleUrl(path.join(packageRoot, 'dist', 'core', 'registry.js'))),
  import(toModuleUrl(path.join(packageRoot, 'dist', 'tools', 'index.js'))),
  import(toModuleUrl(path.join(packageRoot, 'dist', 'resources', 'index.js'))),
  import(toModuleUrl(path.join(packageRoot, 'dist', 'connection', 'websocket.js'))),
  import(toModuleUrl(path.join(packageRoot, 'dist', 'utils', 'errors.js'))),
  import(toModuleUrl(path.join(packageRoot, 'dist', 'utils', 'logger.js'))),
  import(toModuleUrl(path.join(packageRoot, 'dist', 'version.js'))),
  import(toModuleUrl(path.join(packageRoot, 'dist', 'utils', 'connection-strategy.js'))),
]);

const {
  CallToolRequestSchema,
  ListToolsRequestSchema,
  ListResourcesRequestSchema,
  ReadResourceRequestSchema,
} = sdkTypes;

class LazyGodotConnection extends GodotConnection {
  constructor(options = {}) {
    super({ ...options, autoReconnect: false });
  }

  async sendCommand(command, params = {}) {
    if (!this.isConnected) {
      await this.connect();
    }

    return await super.sendCommand(command, params);
  }
}

function registerShutdownHandlers(connection) {
  let shuttingDown = false;

  const shutdown = () => {
    if (shuttingDown) {
      return;
    }

    shuttingDown = true;
    connection.disconnect();
  };

  process.once('beforeExit', shutdown);
  process.once('SIGINT', () => {
    shutdown();
    process.exit(0);
  });
  process.once('SIGTERM', () => {
    shutdown();
    process.exit(0);
  });
}

function createGodotConnection() {
  const host = getTargetHost();
  const port = parsePort(process.env.GODOT_PORT) ?? DEFAULT_GODOT_PORT;
  const strategy = getConnectionStrategy(port);
  const connection = new LazyGodotConnection({ host, port });

  logger.info('Godot connection strategy (lazy wrapper)', {
    environment: strategy.environment,
    targetHost: strategy.targetHost,
    wsUrl: strategy.wsUrl,
    eagerConnect: false,
    autoReconnect: false,
    packageRoot,
    packageVersion: resolvedPackage.version,
    expectedPackageVersion: EXPECTED_PACKAGE_VERSION,
  });

  connection.on('connected', () => {
    logger.info('Connected to Godot');
  });
  connection.on('disconnected', () => {
    logger.warning('Disconnected from Godot');
  });
  connection.on('error', (error) => {
    logger.error('Connection error', { error: error.message });
  });
  connection.on('version_mismatch', ({ serverVersion, addonVersion, projectPath }) => {
    console.error(`[godot-mcp] Version mismatch: server=${serverVersion}, addon=${addonVersion}`);
    console.error(`[godot-mcp] Update addon with: npx @satelliteoflove/godot-mcp --install-addon "${projectPath}"`);
    logger.notice('Version mismatch detected', {
      serverVersion,
      addonVersion,
      projectPath,
    });
  });
  registerShutdownHandlers(connection);
  return connection;
}

registerAllTools();
registerAllResources();

const server = new Server(
  {
    name: 'godot-mcp',
    version: getServerVersion(),
  },
  {
    capabilities: {
      tools: {},
      resources: {},
      logging: {},
    },
  },
);

setMcpServer(server);

const godot = createGodotConnection();

server.setRequestHandler(ListToolsRequestSchema, async () => {
  return { tools: registry.getToolList() };
});

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  try {
    const result = await registry.executeTool(name, args ?? {}, { godot });
    if (typeof result === 'string') {
      return {
        content: [{ type: 'text', text: result }],
      };
    }

    return {
      content: [result],
    };
  } catch (error) {
    let message;
    if (error instanceof GodotCommandError) {
      message = `[${error.code}] ${error.message}`;
    } else if (error instanceof Error) {
      message = error.message;
    } else {
      message = String(error);
    }

    return {
      content: [{ type: 'text', text: `Error: ${message}` }],
      isError: true,
    };
  }
});

server.setRequestHandler(ListResourcesRequestSchema, async () => {
  return { resources: registry.getResourceList() };
});

server.setRequestHandler(ReadResourceRequestSchema, async (request) => {
  const { uri } = request.params;
  const resource = registry.getResourceByUri(uri);

  try {
    const content = await registry.readResource(uri, { godot });
    return {
      contents: [
        {
          uri,
          mimeType: resource?.mimeType ?? 'application/json',
          text: content,
        },
      ],
    };
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    throw new Error(`Failed to read resource: ${message}`);
  }
});

const transport = new StdioServerTransport();
await server.connect(transport);
logger.info('Server started (lazy Godot connection wrapper)', {
  scriptPath: path.join(__dirname, 'godot_mcp_lazy_server.mjs'),
});
