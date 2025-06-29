import { Clarinet, Tx, Chain, Account, types } from '@stacks/transactions';

Clarinet.test({
  name: "Ensure that credits can be minted",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const wallet1 = accounts.get("wallet_1")!;

    let block = chain.mineBlock([
      Tx.contractCall("carbon-credits", "mint-credits", [types.uint(1000)], wallet1.address)
    ]);
    block.receipts[0].result.expectOk().expectUint(1);
  },
});

Clarinet.test({
  name: "Ensure that only verifiers can verify credits",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const deployer = accounts.get("deployer")!;
    const wallet1 = accounts.get("wallet_1")!;

    let block = chain.mineBlock([
      Tx.contractCall("carbon-credits", "set-verifier", [types.principal(wallet1.address), types.bool(true)], deployer.address),
      Tx.contractCall("carbon-credits", "verify-credits", [types.uint(1)], wallet1.address)
    ]);
    block.receipts[1].result.expectOk().expectBool(true);
  },
});

Clarinet.test({
  name: "Ensure credits can be transferred",
  async fn(chain: Chain, accounts: Map<string, Account>) {
    const wallet1 = accounts.get("wallet_1")!;
    const wallet2 = accounts.get("wallet_2")!;

    let block = chain.mineBlock([
      Tx.contractCall("carbon-credits", "mint-credits", [types.uint(1000)], wallet1.address),
      Tx.contractCall("carbon-credits", "transfer-credits", [types.uint(500), types.principal(wallet2.address)], wallet1.address)
    ]);
    block.receipts[1].result.expectOk().expectBool(true);
  },
});
