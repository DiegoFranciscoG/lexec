defmodule Lexec.Privacy.ExclusionTest do
  use ExUnit.Case, async: true

  alias Lexec.Privacy.Exclusion

  test "minors and violence keywords exclude the case" do
    assert {:exclude, "minors", "minors-keywords"} =
             Exclusion.evaluate(%{text: "Se protege el interés superior del niño."})

    assert {:exclude, "minors", _} = Exclusion.evaluate(%{text: "Una ADOLESCENTE de 15 años."})

    assert {:exclude, "violence", "violence-keywords"} =
             Exclusion.evaluate(%{text: "Proceso por violencia intrafamiliar."})

    assert {:exclude, "reserved", _} =
             Exclusion.evaluate(%{text: "Contiene información reservada."})
  end

  test "metadata flags and Court-flagged case numbers exclude without reading text" do
    assert {:exclude, "violence", "metadata-flag-violence"} =
             Exclusion.evaluate(%{text: "", flags: ["violence"]})

    assert Exclusion.evaluate(%{text: "", flags: ["unknown-flag"]}) == :ok
  end

  test "ordinary rulings pass" do
    assert Exclusion.evaluate(%{
             text: "Despido de una trabajadora embarazada.",
             action_type: "EP"
           }) ==
             :ok
  end

  test "rules declare a version" do
    assert Exclusion.rules_version() =~ "excl-"
  end
end
