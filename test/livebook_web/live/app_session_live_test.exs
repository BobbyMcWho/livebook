defmodule LivebookWeb.AppSessionLiveTest do
  use LivebookWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Livebook.TestHelpers

  alias Livebook.{App, Apps, Notebook, Utils}

  test "shows a nonexisting message if the session does not exist", %{conn: conn} do
    slug = Utils.random_short_id()
    app_settings = %{Notebook.AppSettings.new() | slug: slug}
    notebook = %{Notebook.new() | app_settings: app_settings}

    {:ok, app_pid} = Apps.deploy(notebook)

    {:ok, view, _} = live(conn, ~p"/apps/#{slug}/nonexistent")
    assert render(view) =~ "This app session does not exist"
    assert render(view) =~ ~p"/apps/#{slug}"

    App.close(app_pid)
  end

  test "shows a nonexisting message if the session is deactivated", %{conn: conn} do
    slug = Utils.random_short_id()
    app_settings = %{Notebook.AppSettings.new() | slug: slug}
    notebook = %{Notebook.new() | app_settings: app_settings}

    Apps.subscribe()
    {:ok, app_pid} = Apps.deploy(notebook)

    assert_receive {:app_created, %{pid: ^app_pid}}

    assert_receive {:app_updated,
                    %{pid: ^app_pid, sessions: [%{id: session_id, pid: session_pid}]}}

    Livebook.Session.app_deactivate(session_pid)
    assert_receive {:app_updated, %{pid: ^app_pid, sessions: [%{app_status: :deactivated}]}}

    {:ok, view, _} = live(conn, ~p"/apps/#{slug}/#{session_id}")
    assert render(view) =~ "This app session does not exist"
    assert render(view) =~ ~p"/apps/#{slug}"

    App.close(app_pid)
  end

  test "redirects to homepage if the session gets deactivated", %{conn: conn} do
    slug = Utils.random_short_id()
    app_settings = %{Notebook.AppSettings.new() | slug: slug}
    notebook = %{Notebook.new() | app_settings: app_settings}

    Apps.subscribe()
    {:ok, app_pid} = Apps.deploy(notebook)

    assert_receive {:app_created, %{pid: ^app_pid}}

    assert_receive {:app_updated,
                    %{pid: ^app_pid, sessions: [%{id: session_id, pid: session_pid}]}}

    {:ok, view, _} = live(conn, ~p"/apps/#{slug}/#{session_id}")

    Livebook.Session.app_deactivate(session_pid)

    flash = assert_redirect(view, ~p"/")
    assert flash["info"] == "Session has been closed"

    App.close(app_pid)
  end

  test "renders only rich output when output type is rich", %{conn: conn} do
    slug = Livebook.Utils.random_short_id()
    app_settings = %{Livebook.Notebook.AppSettings.new() | slug: slug, output_type: :rich}

    notebook = %{
      Livebook.Notebook.new()
      | app_settings: app_settings,
        sections: [
          %{
            Livebook.Notebook.Section.new()
            | cells: [
                %{
                  Livebook.Notebook.Cell.new(:code)
                  | source: source_for_output({:stdout, "Printed output"})
                },
                %{
                  Livebook.Notebook.Cell.new(:code)
                  | source: source_for_output({:plain_text, "Custom text"})
                }
              ]
          }
        ]
    }

    Livebook.Apps.subscribe()
    {:ok, app_pid} = Apps.deploy(notebook)

    assert_receive {:app_created, %{pid: ^app_pid} = app}
    assert_receive {:app_updated, %{pid: ^app_pid, sessions: [%{app_status: :executed}]}}

    {:ok, view, _} = conn |> live(~p"/apps/#{slug}") |> follow_redirect(conn)

    refute render(view) =~ "Printed output"
    assert render(view) =~ "Custom text"

    Livebook.App.close(app.pid)
  end
end
