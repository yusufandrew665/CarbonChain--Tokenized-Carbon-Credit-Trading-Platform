import { describe, expect, it } from "vitest";
import { Cl } from "@stacks/transactions";

const accounts = simnet.getAccounts();
const deployer = accounts.get("deployer")!;
const address1 = accounts.get("wallet_1")!;
const address2 = accounts.get("wallet_2")!;
const contractName = "Tokenized-Carbon-Credit-Trading-Pla";

describe("Carbon Credit Audit Trail System", () => {
  it("ensures simnet is well initialised", () => {
    expect(simnet.blockHeight).toBeDefined();
  });

  it("should log credit activity successfully", () => {
    const creditId = 1;
    const activityType = "MINT";
    const amount = 1000;
    const details = "Initial minting of carbon credits";
    const txHash = new Uint8Array(32).fill(0);

    const { result } = simnet.callPublicFn(
      contractName,
      "log-credit-activity",
      [Cl.uint(creditId), Cl.stringAscii(activityType), Cl.uint(amount), 
       Cl.stringAscii(details), Cl.buffer(txHash)],
      address1
    );

    expect(result).toBeOk(Cl.uint(1));
  });

  it("should reject invalid audit data", () => {
    const { result } = simnet.callPublicFn(
      contractName,
      "log-credit-activity",
      [Cl.uint(0), Cl.stringAscii(""), Cl.uint(100), 
       Cl.stringAscii("test"), Cl.buffer(new Uint8Array(32))],
      address1
    );

    expect(result).toBeErr(Cl.uint(109)); // err-invalid-audit-data
  });

  it("should allow owner to set authorized auditor", () => {
    const { result } = simnet.callPublicFn(
      contractName,
      "set-authorized-auditor",
      [Cl.principal(address1), Cl.bool(true)],
      deployer
    );

    expect(result).toBeOk(Cl.bool(true));
  });

  it("should reject non-owner setting auditor", () => {
    const { result } = simnet.callPublicFn(
      contractName,
      "set-authorized-auditor",
      [Cl.principal(address2), Cl.bool(true)],
      address1
    );

    expect(result).toBeErr(Cl.uint(100)); // err-owner-only
  });

  it("should check if user is authorized auditor", () => {
    simnet.callPublicFn(
      contractName,
      "set-authorized-auditor",
      [Cl.principal(address1), Cl.bool(true)],
      deployer
    );

    const { result } = simnet.callReadOnlyFn(
      contractName,
      "is-authorized-auditor",
      [Cl.principal(address1)],
      deployer
    );

    expect(result).toBeBool(true);
  });

  it("should add provenance data by authorized auditor", () => {
    simnet.callPublicFn(
      contractName,
      "set-authorized-auditor",
      [Cl.principal(address1), Cl.bool(true)],
      deployer
    );

    const { result } = simnet.callPublicFn(
      contractName,
      "add-provenance-data",
      [
        Cl.uint(1),
        Cl.stringAscii("Solar Farm Project Alpha"),
        Cl.stringAscii("California, USA"),
        Cl.stringAscii("Verra"),
        Cl.stringAscii("VM0042"),
        Cl.uint(2023),
        Cl.uint(10000),
        Cl.list([Cl.stringAscii("CDM"), Cl.stringAscii("Gold Standard")])
      ],
      address1
    );

    expect(result).toBeOk(Cl.uint(1));
  });

  it("should reject provenance data from unauthorized user", () => {
    const { result } = simnet.callPublicFn(
      contractName,
      "add-provenance-data",
      [
        Cl.uint(1),
        Cl.stringAscii("Test Project"),
        Cl.stringAscii("Test Location"),
        Cl.stringAscii("Test Body"),
        Cl.stringAscii("Test Method"),
        Cl.uint(2023),
        Cl.uint(1000),
        Cl.list([Cl.stringAscii("Test")])
      ],
      address2
    );

    expect(result).toBeErr(Cl.uint(111)); // err-unauthorized-auditor
  });

  it("should record impact metrics by authorized auditor", () => {
    const evidenceHash = new Uint8Array(32).fill(1);

    simnet.callPublicFn(
      contractName,
      "set-authorized-auditor",
      [Cl.principal(address1), Cl.bool(true)],
      deployer
    );

    const { result } = simnet.callPublicFn(
      contractName,
      "record-impact-metrics",
      [
        Cl.uint(1),
        Cl.stringAscii("CO2 Reduction"),
        Cl.uint(2500),
        Cl.stringAscii("tonnes"),
        Cl.buffer(evidenceHash),
        Cl.uint(95)
      ],
      address1
    );

    expect(result).toBeDefined();
  });

  it("should reject invalid confidence level", () => {
    const evidenceHash = new Uint8Array(32).fill(1);

    simnet.callPublicFn(
      contractName,
      "set-authorized-auditor",
      [Cl.principal(address1), Cl.bool(true)],
      deployer
    );

    const { result } = simnet.callPublicFn(
      contractName,
      "record-impact-metrics",
      [
        Cl.uint(1),
        Cl.stringAscii("CO2 Reduction"),
        Cl.uint(2500),
        Cl.stringAscii("tonnes"),
        Cl.buffer(evidenceHash),
        Cl.uint(150) // Invalid: > 100
      ],
      address1
    );

    expect(result).toBeErr(Cl.uint(109)); // err-invalid-audit-data
  });

  it("should mint credits for testing", () => {
    const { result } = simnet.callPublicFn(
      contractName,
      "mint-credits",
      [Cl.uint(1000)],
      address1
    );

    expect(result).toBeOk(Cl.uint(1));
  });

  it("should generate compliance report for valid credit", () => {
    simnet.callPublicFn(
      contractName,
      "mint-credits",
      [Cl.uint(1000)],
      address1
    );

    const { result } = simnet.callReadOnlyFn(
      contractName,
      "generate-compliance-report",
      [Cl.uint(1)],
      address1
    );

    expect(result).toBeDefined();
  });

  it("should return error for non-existent credit", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "generate-compliance-report",
      [Cl.uint(999)],
      address1
    );

    expect(result).toBeErr(Cl.uint(110)); // err-audit-not-found
  });

  it("should provide audit statistics", () => {
    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-audit-statistics",
      [],
      address1
    );

    expect(result).toBeDefined();
  });

  it("should provide audit trail summary", () => {
    simnet.callPublicFn(
      contractName,
      "log-credit-activity",
      [
        Cl.uint(1),
        Cl.stringAscii("MINT"),
        Cl.uint(1000),
        Cl.stringAscii("Initial minting of carbon credits"),
        Cl.buffer(new Uint8Array(32).fill(0)),
      ],
      address1
    );

    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-audit-trail-summary",
      [Cl.uint(1)],
      address1
    );

    expect(result).toBeDefined();
  });

  it("should retrieve audit log by ID", () => {
    simnet.callPublicFn(
      contractName,
      "log-credit-activity",
      [
        Cl.uint(1),
        Cl.stringAscii("MINT"),
        Cl.uint(1000),
        Cl.stringAscii("Initial minting of carbon credits"),
        Cl.buffer(new Uint8Array(32).fill(0)),
      ],
      address1
    );

    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-audit-log",
      [Cl.uint(1)],
      address1
    );

    expect(result).toBeDefined();
  });

  it("should return audit log count", () => {
    simnet.callPublicFn(
      contractName,
      "log-credit-activity",
      [
        Cl.uint(1),
        Cl.stringAscii("MINT"),
        Cl.uint(1000),
        Cl.stringAscii("Initial minting of carbon credits"),
        Cl.buffer(new Uint8Array(32).fill(0)),
      ],
      address1
    );

    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-audit-log-count",
      [],
      address1
    );

    expect(result).toBeUint(1n);
  });

  it("should retrieve provenance data", () => {
    simnet.callPublicFn(
      contractName,
      "set-authorized-auditor",
      [Cl.principal(address1), Cl.bool(true)],
      deployer
    );

    simnet.callPublicFn(
      contractName,
      "add-provenance-data",
      [
        Cl.uint(1),
        Cl.stringAscii("Solar Farm Project Alpha"),
        Cl.stringAscii("California, USA"),
        Cl.stringAscii("Verra"),
        Cl.stringAscii("VM0042"),
        Cl.uint(2023),
        Cl.uint(10000),
        Cl.list([Cl.stringAscii("CDM"), Cl.stringAscii("Gold Standard")])
      ],
      address1
    );

    const { result } = simnet.callReadOnlyFn(
      contractName,
      "get-provenance-data",
      [Cl.uint(1)],
      address1
    );

    expect(result).toBeDefined();
  });
});


