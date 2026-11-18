defmodule CauldronNative.Build.AndroidWidgets do
  @moduledoc """
  The Android app's Home Screen widgets (`:widgets` in its config): for each kind a
  Glance widget class and its receiver in a generated `CauldronWidgetKinds.kt`, the
  receiver's manifest entry, and its `appwidget-provider` resource, sized from the
  kind's `sizes`.
  """

  alias CauldronNative.Build.App

  @cells %{small: {2, 2}, medium: {4, 2}, large: {4, 4}, extra_large: {4, 4}}

  @doc "Whether `app` has widgets on Android: kinds with a Home Screen size."
  @spec any?(App.t()) :: boolean()
  def any?(app), do: home_widgets(app) != []

  defp home_widgets(app) do
    for widget <- app.widgets,
        sizes = Enum.filter(widget.sizes, &Map.has_key?(@cells, &1)),
        sizes != [],
        do: %{widget | sizes: sizes}
  end

  @doc "Write the widgets' Kotlin into `java` (the `cauldron/app` source folder) and resources into `res`."
  @spec write!(App.t(), String.t(), String.t()) :: :ok
  def write!(app, java, res) do
    File.write!(Path.join(java, "CauldronWidgetKinds.kt"), kinds(app))
    File.mkdir_p!(Path.join(res, "xml"))
    File.mkdir_p!(Path.join(res, "values"))

    for widget <- home_widgets(app),
        do:
          File.write!(Path.join(res, "xml/cauldron_widget_#{widget.kind}.xml"), provider(widget))

    File.write!(Path.join(res, "values/cauldron_widgets.xml"), strings(app))
  end

  @doc "The manifest's receivers for `app`'s widgets."
  @spec receivers(App.t()) :: String.t()
  def receivers(app) do
    Enum.map_join(home_widgets(app), fn widget ->
      """
              <receiver
                  android:name="cauldron.app.CauldronWidgetReceiver_#{widget.kind}"
                  android:label="@string/cauldron_widget_#{widget.kind}_name"
                  android:exported="true">
                  <intent-filter>
                      <action android:name="android.appwidget.action.APPWIDGET_UPDATE" />
                  </intent-filter>
                  <meta-data
                      android:name="android.appwidget.provider"
                      android:resource="@xml/cauldron_widget_#{widget.kind}" />
              </receiver>
      """
    end)
  end

  defp kinds(app) do
    cases =
      Enum.map_join(
        home_widgets(app),
        "\n",
        &~s|        "#{&1.kind}" -> CauldronWidget_#{&1.kind}()|
      )

    classes =
      Enum.map_join(home_widgets(app), "\n", fn widget ->
        """
        class CauldronWidget_#{widget.kind} : CauldronGlanceWidget("#{widget.kind}", #{kotlin_string(widget.name)})

        class CauldronWidgetReceiver_#{widget.kind} : GlanceAppWidgetReceiver() {
            override val glanceAppWidget: GlanceAppWidget = CauldronWidget_#{widget.kind}()
        }
        """
      end)

    """
    package cauldron.app

    import androidx.glance.appwidget.GlanceAppWidget
    import androidx.glance.appwidget.GlanceAppWidgetReceiver

    object CauldronWidgetKinds {
        fun widget(kind: String): GlanceAppWidget? = when (kind) {
    #{cases}
            else -> null
        }
    }

    #{classes}
    """
  end

  defp provider(widget) do
    cells = Enum.map(widget.sizes, &Map.fetch!(@cells, &1))
    {width, height} = Enum.min_by(cells, fn {columns, rows} -> columns * rows end)
    widest = cells |> Enum.map(&elem(&1, 0)) |> Enum.max()
    tallest = cells |> Enum.map(&elem(&1, 1)) |> Enum.max()

    """
    <?xml version="1.0" encoding="utf-8"?>
    <appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
        android:description="@string/cauldron_widget_#{widget.kind}_description"
        android:initialLayout="@layout/glance_default_loading_layout"
        android:minWidth="#{dp(width)}dp"
        android:minHeight="#{dp(height)}dp"
        android:minResizeWidth="#{dp(width)}dp"
        android:minResizeHeight="#{dp(height)}dp"
        android:maxResizeWidth="#{dp(widest)}dp"
        android:maxResizeHeight="#{dp(tallest)}dp"
        android:targetCellWidth="#{width}"
        android:targetCellHeight="#{height}"
        android:resizeMode="#{resize(cells)}"
        android:updatePeriodMillis="0"
        android:widgetCategory="home_screen" />
    """
  end

  defp resize([_one]), do: "none"
  defp resize(_cells), do: "horizontal|vertical"

  defp dp(cells), do: cells * 70 - 30

  defp strings(app) do
    entries =
      Enum.map_join(home_widgets(app), "\n", fn widget ->
        """
            <string name="cauldron_widget_#{widget.kind}_name">#{xml(widget.name)}</string>
            <string name="cauldron_widget_#{widget.kind}_description">#{xml(widget.description)}</string>
        """
      end)

    """
    <?xml version="1.0" encoding="utf-8"?>
    <resources>
    #{entries}</resources>
    """
  end

  defp xml(text) do
    text
    |> String.replace("&", "&amp;")
    |> String.replace("<", "&lt;")
    |> String.replace("'", "\\'")
    |> String.replace("\"", "\\\"")
  end

  defp kotlin_string(text), do: text |> JSON.encode!() |> String.replace("$", "\\$")
end
