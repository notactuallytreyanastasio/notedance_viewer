defmodule Dave.NFM.Fetch do
  @moduledoc """
  Fetching a score off a Noteflight Learning site, no login needed.

  Discovered on a real Learning score (Mary Had a Little Lamb, Burlington
  Public Schools):

      /score_data/<id>        JSON metadata: title, composer, duration, and
                              score_contents_url / score_latest_version
      /score_content/<id>/<v> NFMXML, zlib+base64 inside <noteflightCompressed>

  The number after the id is a VERSION. Every save in Noteflight makes a
  new one (Mandalorian was on 55 the day Dave pasted it) and this module
  used to ask for 16, the Mary score's latest at the time, so it imported
  a draft from months before. Now the content address comes from
  `score_data`'s `score_contents_url`, which names the latest version;
  without one, `/score_content/<id>` with no version also answers with
  the latest (checked: same bytes as /55, /latest and /999).

  Both endpoints answer an anonymous GET on the Learning host.
  """

  @doc """
  Split a Noteflight URL into `{host, score_id}`.

      "https://mflms-bsdk5.learning.noteflight.com/scores/view/eea68d..."
      => {"mflms-bsdk5.learning.noteflight.com", "eea68d..."}
  """
  def parse_url(url) do
    # A pasted address may carry a trailing slash, a query string (?share=…)
    # or a fragment; the 40-hex id is the only part that matters.
    case Regex.run(
           ~r|^https?://([^/?#]+)/scores/view/([0-9a-f]{40})(?:[/?#].*)?$|i,
           String.trim(url)
         ) do
      [_, host, id] -> {host, String.downcase(id)}
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
    metadata = fetch_metadata(host, id)
    compressed_req = Req.get!(url: content_url(host, id, metadata))
    {inflate(compressed_req.body), metadata}
  end

  @doc """
  The address of the score's latest content: what `score_data` says, else
  the unversioned endpoint. Never a fixed version number.
  """
  def content_url(host, id, metadata) do
    case metadata do
      %{"score_contents_url" => "https://" <> _ = url} -> url
      _ -> "https://#{host}/score_content/#{id}"
    end
  end

  @doc "The version `score_data` calls latest, or nil when it does not say."
  def version(%{"score_latest_version" => %{"version_id" => v}}) when is_integer(v), do: v
  def version(_metadata), do: nil

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
end
