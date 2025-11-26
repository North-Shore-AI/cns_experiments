defmodule Mix.Tasks.CnsCrucible.TopologyDemo do
  @moduledoc """
  Walk a tiny synthetic claim graph through the CNS adapters so you can see how
  they delegate into `CNS.Topology` (and ultimately `ex_topology`).

  ## Usage

      mix cns_crucible.topology_demo
  """

  use Mix.Task

  @shortdoc "Run a topology walkthrough via CNS adapters"

  alias CnsCrucible.Adapters.{Common, Surrogates, TDA}
  alias CNS.Topology

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.start")

    {examples, outputs} = sample_payload()

    with {:ok, %{snos: snos}} <- Common.build_snos(examples, outputs) do
      IO.puts("\n== Graph invariants via CNS.Topology (ExTopology facade) ==")
      IO.inspect(Topology.invariants(snos))

      IO.puts("\n== Surrogates via CnsCrucible.Adapters.Surrogates ==")

      {:ok, %{results: sur_results, summary: sur_summary}} =
        Surrogates.compute_surrogates(examples, outputs)

      IO.inspect(sur_summary, label: "Surrogate summary")
      IO.inspect(sur_results, label: "Per-claim surrogates")

      IO.puts("\n== Persistent homology via CnsCrucible.Adapters.TDA ==")
      {:ok, %{summary: tda_summary}} = TDA.compute_tda(examples, outputs, max_dimension: 1)
      IO.inspect(tda_summary, label: "TDA summary")
    else
      {:error, reason} ->
        Mix.raise("Failed to build SNOs for demo: #{inspect(reason)}")
    end
  end

  defp sample_payload do
    examples = [
      %{
        "prompt" => "Doc A: regular exercise improves mood and sleep.",
        "completion" => "Doc B: downstream benefits of sleep on focus.",
        "metadata" => %{"doc_ids" => ["D1", "D2"]}
      }
    ]

    outputs = [
      """
      CLAIM[C1]: Regular exercise improves sleep quality
      CLAIM[C2]: Better sleep quality boosts next-day focus
      CLAIM[C3]: Better focus encourages regular exercise
      RELATION: C1 supports C2
      RELATION: C2 supports C3
      RELATION: C3 supports C1
      """
    ]

    {examples, outputs}
  end
end
