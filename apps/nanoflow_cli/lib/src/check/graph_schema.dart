/// The JSON Schema (draft 2020-12) of the structure of a graph: the keys of
/// the graph and of its nodes, and the type of every value.
///
/// It catches typos in keys and values of the wrong type. What it cannot
/// say — that targets name existing nodes, that lists have no repeats, that
/// every node is reachable — is checked in Dart after it passes.
///
/// `package:ack` runs it as it is (`Ack.fromJsonSchema`); every keyword here
/// is one ack imports. A node is a worker or a fork through `oneOf` rather
/// than `if`/`then`/`else`, which ack does not import; the two never both
/// match, because each forbids the other's key.
///
/// The type-specific keywords of a value that may have several types apply
/// only to the type they are for: `minLength` to a string, `items` to an
/// array, `additionalProperties` to an object.
const Map<String, Object?> graphSchema = {
  r'$schema': 'https://json-schema.org/draft/2020-12/schema',
  'type': 'object',
  'required': ['start', 'nodes'],
  'properties': {
    'start': {r'$ref': r'#/$defs/target'},
    // Named data types: each one a schema of its own.
    'types': {
      'type': 'object',
      'additionalProperties': {r'$ref': r'#/$defs/schema'},
    },
    // Nodes by name, in declaration order.
    'nodes': {
      'type': 'object',
      'additionalProperties': {r'$ref': r'#/$defs/node'},
    },
  },
  'additionalProperties': false,
  r'$defs': {
    'node': {
      'type': 'object',
      'oneOf': [
        {r'$ref': r'#/$defs/worker'},
        {r'$ref': r'#/$defs/fork'},
      ],
    },
    'worker': {
      'type': 'object',
      'required': ['command'],
      'properties': {
        'command': {r'$ref': r'#/$defs/command'},
        'in': {r'$ref': r'#/$defs/schema'},
        'out': {r'$ref': r'#/$defs/schema'},
        'then': {r'$ref': r'#/$defs/target'},
      },
      'additionalProperties': false,
    },
    'fork': {
      'type': 'object',
      'required': ['decide', 'then'],
      'properties': {
        'decide': {r'$ref': r'#/$defs/command'},
        'in': {r'$ref': r'#/$defs/schema'},
        'then': {r'$ref': r'#/$defs/forkThen'},
        'else': {r'$ref': r'#/$defs/target'},
      },
      'additionalProperties': false,
    },
    // What a node runs: a shell command or, in a graph in code, the place of
    // its function.
    'command': {'type': 'string', 'minLength': 1},
    // The `in` or `out` of a node, or a named type: a JSON Schema.
    'schema': {
      'type': ['object', 'boolean'],
    },
    // A node name, or a list of them; an empty list leads nowhere.
    'target': {
      'type': ['string', 'array'],
      'minLength': 1,
      'items': {r'$ref': r'#/$defs/name'},
    },
    // A target (if), or a map of outcomes to targets (switch).
    'forkThen': {
      'type': ['string', 'array', 'object'],
      'minLength': 1,
      'items': {r'$ref': r'#/$defs/name'},
      'additionalProperties': {r'$ref': r'#/$defs/target'},
    },
    'name': {'type': 'string', 'minLength': 1},
  },
};
