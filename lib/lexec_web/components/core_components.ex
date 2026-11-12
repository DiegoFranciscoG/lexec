defmodule LexecWeb.CoreComponents do
  @moduledoc "Small accessible building blocks shared by every page."
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  attr :kind, :atom, values: [:info, :error], required: true
  attr :flash, :map, required: true

  def flash(assigns) do
    ~H"""
    <div
      :if={msg = Phoenix.Flash.get(@flash, @kind)}
      id={"flash-#{@kind}"}
      class={["flash", @kind == :error && "flash--error"]}
      role={if @kind == :error, do: "alert", else: "status"}
    >
      <p>{msg}</p>
      <button
        type="button"
        class="btn"
        phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> JS.hide(to: "#flash-#{@kind}")}
      >
        Cerrar aviso
      </button>
    </div>
    """
  end

  @doc "Labelled form field with its errors. `type` may be text, email, number, textarea, select or checkbox."
  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "text"
  attr :hint, :string, default: nil
  attr :options, :list, default: []

  attr :rest, :global,
    include: ~w(autocomplete maxlength minlength required inputmode placeholder)

  def field(%{type: "checkbox"} = assigns) do
    assigns = assign_errors(assigns)

    ~H"""
    <div class="field">
      <input type="hidden" name={@field.name} value="false" />
      <label class="check" for={@field.id}>
        <input
          type="checkbox"
          id={@field.id}
          name={@field.name}
          value="true"
          checked={Phoenix.HTML.Form.normalize_value("checkbox", @field.value)}
          aria-invalid={@errors != [] && "true"}
          aria-describedby={@errors != [] && "#{@field.id}-error"}
          {@rest}
        />
        <span>{@label}</span>
      </label>
      <.errors id={"#{@field.id}-error"} errors={@errors} />
    </div>
    """
  end

  def field(assigns) do
    assigns = assign_errors(assigns)

    ~H"""
    <div class="field">
      <label for={@field.id}>{@label}</label>
      <p :if={@hint} class="hint" id={"#{@field.id}-hint"}>{@hint}</p>
      <textarea
        :if={@type == "textarea"}
        id={@field.id}
        name={@field.name}
        class="textarea"
        aria-invalid={@errors != [] && "true"}
        aria-describedby={describedby(@field.id, @hint, @errors)}
        {@rest}
      >{Phoenix.HTML.Form.normalize_value("textarea", @field.value)}</textarea>
      <select
        :if={@type == "select"}
        id={@field.id}
        name={@field.name}
        class="select"
        aria-invalid={@errors != [] && "true"}
        aria-describedby={describedby(@field.id, @hint, @errors)}
        {@rest}
      >
        {Phoenix.HTML.Form.options_for_select(@options, @field.value)}
      </select>
      <input
        :if={@type not in ["textarea", "select"]}
        type={@type}
        id={@field.id}
        name={@field.name}
        value={Phoenix.HTML.Form.normalize_value(@type, @field.value)}
        class="input"
        aria-invalid={@errors != [] && "true"}
        aria-describedby={describedby(@field.id, @hint, @errors)}
        {@rest}
      />
      <.errors id={"#{@field.id}-error"} errors={@errors} />
    </div>
    """
  end

  attr :id, :string, required: true
  attr :errors, :list, required: true

  defp errors(assigns) do
    ~H"""
    <p :if={@errors != []} class="error" id={@id}>{Enum.join(@errors, ". ")}</p>
    """
  end

  defp assign_errors(%{field: field} = assigns) do
    errors =
      if Phoenix.Component.used_input?(field),
        do: Enum.map(field.errors, &translate_error/1),
        else: []

    assign(assigns, :errors, errors)
  end

  defp describedby(id, hint, errors) do
    [hint && "#{id}-hint", errors != [] && "#{id}-error"]
    |> Enum.filter(&is_binary/1)
    |> case do
      [] -> nil
      ids -> Enum.join(ids, " ")
    end
  end

  @doc "Spanish messages for the default Ecto validations."
  def translate_error({msg, opts}) do
    msg =
      case msg do
        "can't be blank" -> "es obligatorio"
        "is invalid" -> "no es válido"
        "has invalid format" -> "tiene un formato no válido"
        "should be at least %{count} character(s)" -> "debe tener al menos %{count} caracteres"
        "should be at most %{count} character(s)" -> "debe tener como máximo %{count} caracteres"
        "must be greater than %{number}" -> "debe ser mayor que %{number}"
        "must be less than %{number}" -> "debe ser menor que %{number}"
        other -> other
      end

    Enum.reduce(opts, msg, fn {key, value}, acc ->
      String.replace(acc, "%{#{key}}", fn _ -> to_string(value) end)
    end)
  end

  @doc "External link to the official document, announced as such to screen readers."
  attr :href, :string, required: true
  slot :inner_block, required: true

  def official_link(assigns) do
    ~H"""
    <a href={@href} class="link" rel="noopener noreferrer external" target="_blank" data-official>
      {render_slot(@inner_block)}<span class="visually-hidden"> (documento oficial, se abre en una pestaña nueva)</span><svg
        class="icon-external"
        viewBox="0 0 20 20"
        aria-hidden="true"
        focusable="false"
      ><path
        d="M11 3h6v6M17 3l-8 8M8 5H4v11h11v-4"
        fill="none"
        stroke="currentColor"
        stroke-width="1.6"
      /></svg>
    </a>
    """
  end
end
