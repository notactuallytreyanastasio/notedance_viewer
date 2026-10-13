defmodule Dave.NFM.Form do
  @moduledoc """
  The playback order of a score's bars: repeats, segno, coda, "D.S. al
  Coda" and friends unrolled into a flat list of measure indices.

  Marks come from `Dave.NFM.Parser` as `%{bar: 31, kind: :start_repeat}`
  (bars are 1-based, like the printed numbers). A sign that sits at the
  START of a bar: `:start_repeat`, `:segno`, `:coda`. A mark that acts at
  the END of its bar: `:end_repeat`, `:to_coda`, `:ds_al_coda`,
  `:dc_al_coda`, `:ds_al_fine`, `:dc_al_fine`, `:ds`, `:dc`, `:fine`.

  Rules, in the order they are tried at the end of each bar:

    * `:fine` ends the piece, but only after a "D.S. al Fine" / "D.C. al
       Fine" jump; before the jump it is just a word.
    * `:to_coda` jumps to the `:coda` bar, but only after an "al Coda"
       jump; before it, play on.
    * `:end_repeat` goes back to the nearest `:start_repeat` at or before
       it (or bar 1 when there is none, as in Twinkle) the FIRST time it
       is reached. A repeat already taken is not taken again. A repeat
       first met after a jump is still taken (Nine to Five's coda, bars
       31-38, is only reached through the D.S. and its repeat is played):
       the convention that repeats are skipped after a D.S. applies to
       bars already heard, and these never were.
    * `:ds_*` jumps to the `:segno` bar, `:dc_*` to bar 1, once.

  A score whose marks never let it end raises after 50 passes.
  """

  @jumps [:ds_al_coda, :dc_al_coda, :ds_al_fine, :dc_al_fine, :ds, :dc]

  @doc "Measure indices (0-based) in the order they are played."
  def unroll(marks, bar_count) when bar_count > 0 do
    by_bar = Enum.group_by(marks, & &1.bar, & &1.kind)
    kinds = fn bar -> Map.get(by_bar, bar, []) end
    segno = find_bar(marks, :segno)
    coda = find_bar(marks, :coda)

    starts = marks |> Enum.filter(&(&1.kind == :start_repeat)) |> Enum.map(& &1.bar)

    walk(0, bar_count, kinds, %{taken: MapSet.new(), jumped: nil, segno: segno, coda: coda, starts: starts}, [], 0)
  end

  defp walk(_i, bar_count, _kinds, _st, _acc, n) when n > bar_count * 50 do
    raise ArgumentError, "TODO: the repeats and jumps never let this score end (#{n} bars played)"
  end

  defp walk(i, bar_count, kinds, st, acc, n) do
    acc = [i | acc]
    bar = i + 1
    here = kinds.(bar)
    jump = Enum.find(@jumps, &(&1 in here))

    cond do
      :fine in here and st.jumped in [:ds_al_fine, :dc_al_fine] ->
        Enum.reverse(acc)

      :to_coda in here and st.jumped in [:ds_al_coda, :dc_al_coda] ->
        walk(st.coda - 1, bar_count, kinds, st, acc, n + 1)

      :end_repeat in here and not MapSet.member?(st.taken, bar) ->
        start = st.starts |> Enum.filter(&(&1 <= bar)) |> Enum.max(fn -> 1 end)
        walk(start - 1, bar_count, kinds, %{st | taken: MapSet.put(st.taken, bar)}, acc, n + 1)

      jump != nil and st.jumped == nil ->
        target = if jump in [:ds_al_coda, :ds_al_fine, :ds], do: st.segno, else: 1
        walk(target - 1, bar_count, kinds, %{st | jumped: jump}, acc, n + 1)

      i + 1 < bar_count ->
        walk(i + 1, bar_count, kinds, st, acc, n + 1)

      true ->
        Enum.reverse(acc)
    end
  end

  defp find_bar(marks, kind) do
    case Enum.find(marks, &(&1.kind == kind)) do
      %{bar: bar} -> bar
      nil -> nil
    end
  end

  @doc """
  The sentence the import flash shows when a score has a form, so Dave
  knows the clock will go round; nil when it has none.
  """
  def describe([]), do: nil

  def describe(marks) do
    names = %{
      start_repeat: "a repeat",
      end_repeat: nil,
      segno: "a segno",
      coda: "a coda",
      to_coda: "“To Coda”",
      ds_al_coda: "“D.S. al Coda”",
      dc_al_coda: "“D.C. al Coda”",
      ds_al_fine: "“D.S. al Fine”",
      dc_al_fine: "“D.C. al Fine”",
      ds: "“D.S.”",
      dc: "“D.C.”",
      fine: "“Fine”"
    }

    marks
    |> Enum.map(fn %{bar: bar, kind: kind} ->
      case names[kind] do
        nil -> if kind == :end_repeat and not Enum.any?(marks, &(&1.kind == :start_repeat)), do: "a repeat of bars 1 to #{bar}", else: nil
        name -> "#{name} at bar #{bar}"
      end
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join(", ")
    |> then(&"This song has #{&1}; the line and the clock follow them.")
  end
end
