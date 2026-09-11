defmodule Keepling.Repo.Migrations.AddCommandReceiptsIssuingGrant do
  use Ecto.Migration

  # T-06-07-01/D-39. Closes the receipt-scope inversion: today any grant
  # holding `tasks.write` may read any account mutation's receipt, and the
  # only thing preventing a cross-grant read is that mutation ids are not
  # enumerable -- a coincidence of identifier choice, not a control. Recording
  # which grant issued a mutation lets `Commands.lookup_result/3` bind a
  # read to its issuing grant. Nullable: a receipt written before this
  # column existed, or issued by a browser session (which has no device
  # grant), records no issuer and is never subject to the ownership check --
  # only an explicit MISMATCH refuses, never an absent value.
  def change do
    alter table(:command_receipts) do
      add :issuing_grant_id, references(:device_grants, type: :uuid, on_delete: :nilify_all)
    end
  end
end
