defmodule CnsCrucible.Adapters.TDA do
  @moduledoc """
  CNS-based implementation of `Crucible.CNS.TDAAdapter`.
  """

  @behaviour Crucible.CNS.TDAAdapter

  require Logger

  alias CNS.Topology
  alias CNS.Topology.{Adapter, Persistence}
  alias CnsCrucible.Adapters.Common
  alias ExTopology.Diagram

  @impl true
  def compute_tda(examples, outputs, opts \\ %{}) do
    opts = normalize_opts(opts)

    with {:ok, %{snos: snos}} <- Common.build_snos(examples, outputs) do
      snos = ensure_embeddings(snos)

      with {:ok, result} <- safe_compute_tda(snos, opts) do
        {results, summary} = format_result(result, length(snos))
        {:ok, %{results: results, summary: summary}}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp safe_compute_tda(snos, opts) do
    try do
      {:ok, Persistence.compute(snos, opts)}
    rescue
      e -> {:ok, fallback_result(snos, e)}
    end
  end

  defp format_result(%{diagrams: diagrams} = result, count) do
    diag_map = diagram_barcodes(diagrams)
    cycles = Map.get(result.circular_reasoning, :detected_cycles, 0)
    persistent_cycles = Map.get(result.circular_reasoning, :persistent_cycles, 0)
    clusters = Map.get(result.cluster_analysis, :total_clusters, 0)
    voids = Map.get(result.higher_order, :voids, 0)
    fallback_reason = Map.get(result, :error)

    results = [
      %{
        sno_id: "network",
        betti: %{0 => clusters, 1 => cycles, 2 => voids},
        diagrams: diag_map,
        summary: %{
          total_features: Map.get(result.summary, :total_features, 0),
          max_persistence: max_persistence(diagrams),
          mean_persistence: mean_persistence(diagrams),
          persistent_cycle_ratio: safe_div(persistent_cycles, count),
          notes:
            if(fallback_reason,
              do: "Fallback summary (approx): #{inspect(fallback_reason)}",
              else: Map.get(result.circular_reasoning, :interpretation, nil)
            )
        }
      }
    ]

    summary = %{
      beta0_mean: safe_div(clusters, count),
      beta1_mean: safe_div(cycles, count),
      beta2_mean: safe_div(voids, count),
      high_loop_fraction: safe_div(persistent_cycles, count),
      avg_persistence: mean_persistence(diagrams),
      n_snos: count
    }

    summary =
      case fallback_reason do
        nil -> summary
        reason -> Map.merge(summary, %{status: :fallback, reason: inspect(reason)})
      end

    {results, summary}
  end

  defp format_result(_result, count), do: {[], default_summary(count)}

  defp diagram_barcodes(diagrams) do
    diagrams
    |> Enum.map(fn %{dimension: dim, pairs: pairs} ->
      {dim,
       Enum.map(pairs, fn {birth, death} ->
         %{
           birth: birth,
           death: death,
           persistence:
             case death do
               :infinity -> :infinity
               _ -> death - birth
             end
         }
       end)}
    end)
    |> Map.new()
  end

  defp mean_persistence(diagrams) do
    diagrams
    |> Enum.flat_map(&Diagram.persistences/1)
    |> Enum.reject(&(&1 == :infinity))
    |> case do
      [] -> 0.0
      list -> Enum.sum(list) / length(list)
    end
  end

  defp max_persistence(diagrams) do
    diagrams
    |> Enum.flat_map(&Diagram.persistences/1)
    |> Enum.reject(&(&1 == :infinity))
    |> case do
      [] -> 0.0
      list -> Enum.max(list)
    end
  end

  defp safe_div(_num, 0), do: 0.0
  defp safe_div(num, den), do: num / den

  defp ensure_embeddings(snos) do
    snos
    |> Enum.with_index()
    |> Enum.map(fn {%{metadata: meta} = sno, idx} ->
      cond do
        Map.has_key?(meta, :embedding) or Map.has_key?(meta, "embedding") ->
          sno

        true ->
          case Adapter.extract_embedding(sno, source: :generate) do
            {:ok, embedding} ->
              Logger.info(
                "[CnsCrucible.Adapters.TDA] embedding_provider used for #{sno.id || idx}"
              )

              %{sno | metadata: Map.put(meta, :embedding, embedding)}

            {:error, reason} ->
              Logger.error(
                "[CnsCrucible.Adapters.TDA] embedding missing for #{sno.id || idx}: #{inspect(reason)}"
              )

              raise "Embedding unavailable (see logs)"

            other ->
              Logger.error(
                "[CnsCrucible.Adapters.TDA] embedding missing for #{sno.id || idx}: #{inspect(other)}"
              )

              raise "Embedding unavailable (see logs)"
          end
      end
    end)
  end

  defp default_summary(count, extra \\ %{}) do
    Map.merge(
      %{
        beta0_mean: 0.0,
        beta1_mean: 0.0,
        beta2_mean: 0.0,
        high_loop_fraction: 0.0,
        avg_persistence: 0.0,
        n_snos: count
      },
      extra
    )
  end

  defp normalize_opts(nil), do: []
  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)
  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(_), do: []

  defp fallback_result(snos, error) do
    graph = Topology.build_graph(snos)
    betti = Topology.betti_numbers(graph)

    %{
      cluster_analysis: %{
        total_clusters: betti.b0,
        persistent_clusters: betti.b0,
        cluster_stability: 0.0,
        cluster_entropy: 0.0
      },
      circular_reasoning: %{
        detected_cycles: betti.b1,
        persistent_cycles: betti.b1,
        cycle_severity: 0.0,
        max_cycle_persistence: 0.0,
        interpretation: :approximate
      },
      higher_order: %{
        voids: 0,
        complexity: 0.0,
        max_void_persistence: 0.0
      },
      diagrams: [],
      summary: %{
        total_features: betti.b0 + betti.b1,
        significant_features: 0,
        overall_complexity: 0.0,
        topological_robustness: 0.0
      },
      error: error
    }
  end
end
