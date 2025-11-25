defmodule CnsCrucible.Experiments.ClaimExtraction do
  @moduledoc """
  Backwards-compatible entry point for claim extraction experiments.

  Delegates to `CnsCrucible.Experiments.ScifactClaimExtraction`, which runs
  the canonical Crucible pipeline.
  """

  def run(opts \\ []), do: CnsCrucible.Experiments.ScifactClaimExtraction.run(opts)
end
