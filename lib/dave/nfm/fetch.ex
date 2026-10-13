defmodule Dave.NFM.Fetch do
  @moduledoc """
  Fetching a score off a Noteflight Learning site, no login needed.

  Discovered on a real Learning score (Mary Had a Little Lamb, Burlington
  Public Schools):

      /score_data/<id>       JSON metadata (title, composer, duration)
      /score_content/<id>/16 NFMXML, zlib+base64 inside <noteflightCompressed>

  Both endpoints answer an anonymous GET on the Learning host.
  """

  @content_version "16"

  @doc """
  Split a Noteflight URL into `{host, score_id}`.

      "https://mflms-bsdk5.learning.noteflight.com/scores/view/eea68d..."
      => {"mflms-bsdk5.learning.noteflight.com", "eea68d..."}
  """
  def parse_url(url) do
    case Regex.run(~r|^https?://([^/]+)/scores/view/([0-9a-f]{40})$|i, String.trim(url)) do
      [_, host, id] -> {host, id}
      nil -> raise ArgumentError, "not a Noteflight score URL: #{inspect(url)}"
    end
  end

  @doc """
  Fetch a score by URL (or `{host, id}` pair) and inflate it to raw NFMXML.
  """
  def fetch(url_or_pair)

  def fetch(url) when is_binary(url) do
    {host, id} = parse_url(url)
    fetch({host, id})
  end

  def fetch({host, id}) do
    compressed_req = Req.get!(url: "https://#{host}/score_content/#{id}/#{content_version()}")
    inflated = inflate(compressed_req.body)
    metadata = fetch_metadata(host, id)
    {inflated, metadata}
  end

  def fetch_metadata(host, id) do
    case Req.get(url: "https://#{host}/score_data/#{id}") do
      {:ok, %{status: 200, body: %{"score_data" => data}}} -> data
      _ -> %{}
    end
  end

  @doc """
  Inflate the `<noteflightCompressed>` envelope: base64 body, zlib stream
  (starts 0x78 0x9c), inflates to the NFMXML document.

  Fed incrementally with `safeInflate` on purpose: OTP 28's one-shot
  `:zlib.unzip/1` returns `:data_error` on these exact streams — verified
  byte-for-byte, Python `zlib.decompress` inflates the same payload to the
  same 20186 bytes — while the incremental loop completes cleanly.
  """
  def inflate(compressed_xml) when is_binary(compressed_xml) do
    compressed_xml
    |> capture_payload()
    |> Base.decode64!()
    |> inflate_zlib()
  rescue
    e in ArgumentError ->
      reraise "not a <noteflightCompressed> payload: #{Exception.message(e)}",
              __STACKTRACE__
  end

  defp inflate_zlib(raw) do
    z = :zlib.open()
    :ok = :zlib.inflateInit(z)

    try do
      loop_inflate(z, :zlib.safeInflate(z, raw), "")
    after
      :zlib.close(z)
    end
  end

  defp loop_inflate(_z, {:finished, chunks}, acc), do: acc <> IO.iodata_to_binary(chunks)

  defp loop_inflate(z, {:continue, chunks}, acc),
    do: loop_inflate(z, :zlib.safeInflate(z, []), acc <> IO.iodata_to_binary(chunks))

  defp capture_payload(xml) do
    case Regex.run(~r|<noteflightCompressed>(.*?)</noteflightCompressed>|s, xml) do
      [_, payload] ->
        payload

      nil ->
        raise ArgumentError,
              "no <noteflightCompressed> in body (first 200 bytes: #{binary_part(xml, 0, min(byte_size(xml), 200))})"
    end
  end

  defp content_version, do: @content_version
end
