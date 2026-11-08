// Minimal adapter for Lokal's existing QuickJS engine. The host bridge and
// config are deliberately not exposed to the player or solver. QuickJS supplies
// no browser, filesystem or network APIs in this context.
(function () {
  let solver;
  globalThis.registerExtension = value => { solver = value; };
  return {
    registered: () => typeof solver?.solve === 'function',
    methods: () => JSON.stringify(['solve']),
    invoke: (name, args) => {
      if (name !== 'solve') throw Error('Unsupported solver method');
      return JSON.stringify(solver.solve(...JSON.parse(args)));
    },
    callback: () => '',
  };
})
