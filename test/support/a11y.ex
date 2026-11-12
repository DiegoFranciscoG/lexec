defmodule Lexec.A11y do
  @moduledoc """
  Automated subset of WCAG 2.2 AA checks on rendered HTML (T-12), plus a
  contrast calculator for the design tokens (oklch → sRGB → WCAG ratio).
  Manual checks (screen reader, zoom, keyboard order) are documented in the README.
  """

  import ExUnit.Assertions

  @doc "Asserts structural WCAG checks on a full HTML document."
  def assert_accessible(html) do
    doc = LazyHTML.from_document(html)

    # 3.1.1 language of page
    assert LazyHTML.attribute(LazyHTML.query(doc, "html"), "lang") == ["es"]

    # 2.4.2 page titled
    assert [title] = doc |> LazyHTML.query("head > title") |> Enum.map(&LazyHTML.text/1)
    assert String.trim(title) != ""

    # 2.4.1 bypass blocks: skip link to an existing main landmark
    assert ["#contenido"] = doc |> LazyHTML.query("a.skip-link") |> LazyHTML.attribute("href")
    assert [_] = Enum.to_list(LazyHTML.query(doc, "main#contenido"))
    refute Enum.empty?(LazyHTML.query(doc, "nav[aria-label]"))

    # 1.3.1 one h1 and no skipped heading levels
    headings =
      doc
      |> LazyHTML.query("h1, h2, h3, h4, h5, h6")
      |> Enum.map(fn node ->
        node |> LazyHTML.tag() |> hd() |> String.slice(1, 1) |> String.to_integer()
      end)

    assert Enum.count(headings, &(&1 == 1)) == 1, "exactly one h1"

    for [previous, level] <- Enum.chunk_every([0 | headings], 2, 1, :discard) do
      assert level <= previous + 1, "heading jumps from h#{previous} to h#{level}"
    end

    # 3.3.2 / 4.1.2 every form control has an accessible name
    labelled_ids =
      doc |> LazyHTML.query("label[for]") |> LazyHTML.attribute("for") |> MapSet.new()

    for control <- LazyHTML.query(doc, "input:not([type=hidden]), select, textarea") do
      [id] = attr_or_nil(control, "id")
      aria = attr_or_nil(control, "aria-label") ++ attr_or_nil(control, "aria-labelledby")
      wrapped? = inside_label?(doc, control)

      assert (is_binary(id) and MapSet.member?(labelled_ids, id)) or Enum.any?(aria, &is_binary/1) or
               wrapped?,
             "control without label: #{LazyHTML.to_html(control)}"
    end

    # 1.1.1 images have alternatives; meaningful SVGs have a title
    for img <- LazyHTML.query(doc, "img") do
      assert [alt] = LazyHTML.attribute(img, "alt"), "img without alt"
      assert is_binary(alt)
    end

    for svg <- LazyHTML.query(doc, "svg[role=img]") do
      assert Enum.count(LazyHTML.query(svg, "title")) == 1
    end

    for svg <- LazyHTML.query(doc, "svg:not([role=img])") do
      assert LazyHTML.attribute(svg, "aria-hidden") == ["true"],
             "decorative svg must be aria-hidden"
    end

    # 2.4.4 / 4.1.2 links and buttons have a name
    for el <- LazyHTML.query(doc, "a[href], button") do
      name = LazyHTML.text(el) |> String.trim()
      aria = LazyHTML.attribute(el, "aria-label")
      assert name != "" or aria != [], "element without accessible name: #{LazyHTML.to_html(el)}"
    end

    # 2.4.3 no positive tabindex
    for value <- doc |> LazyHTML.query("[tabindex]") |> LazyHTML.attribute("tabindex") do
      assert String.to_integer(value) <= 0
    end

    # Unique ids (4.1.1 parsing hygiene, needed by label[for])
    ids = doc |> LazyHTML.query("[id]") |> LazyHTML.attribute("id")
    assert ids -- Enum.uniq(ids) == [], "duplicate ids: #{inspect(ids -- Enum.uniq(ids))}"

    doc
  end

  defp attr_or_nil(node, name) do
    case LazyHTML.attribute(node, name) do
      [] -> [nil]
      values -> values
    end
  end

  defp inside_label?(doc, control) do
    target = LazyHTML.to_html(control)
    doc |> LazyHTML.query("label") |> Enum.any?(&String.contains?(LazyHTML.to_html(&1), target))
  end

  # ---- contrast -------------------------------------------------------------

  @doc "Reads `--name: oklch(L% C H)` tokens from tokens.css."
  def tokens do
    css = File.read!(Path.expand("../../assets/css/tokens.css", __DIR__))

    ~r/--color-([a-z0-9-]+):\s*oklch\(([\d.]+)%\s+([\d.]+)\s+([\d.]+)\)/
    |> Regex.scan(css)
    |> Map.new(fn [_, name, l, c, h] ->
      {name, {num(l) / 100, num(c), num(h)}}
    end)
  end

  defp num(text), do: text |> Float.parse() |> elem(0)

  @doc "WCAG contrast ratio between two oklch colours."
  def contrast(a, b) do
    [la, lb] = Enum.map([a, b], &luminance/1) |> Enum.sort(:desc)
    (la + 0.05) / (lb + 0.05)
  end

  defp luminance({l, c, h}) do
    hr = h * :math.pi() / 180
    {a, b} = {c * :math.cos(hr), c * :math.sin(hr)}

    l_ = l + 0.3963377774 * a + 0.2158037573 * b
    m_ = l - 0.1055613458 * a - 0.0638541728 * b
    s_ = l - 0.0894841775 * a - 1.2914855480 * b
    {lc, mc, sc} = {l_ * l_ * l_, m_ * m_ * m_, s_ * s_ * s_}

    r = clamp(4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc)
    g = clamp(-1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc)
    bl = clamp(-0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc)

    0.2126 * r + 0.7152 * g + 0.0722 * bl
  end

  defp clamp(v), do: v |> max(0.0) |> min(1.0)
end
