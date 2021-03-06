defmodule Phoenix.Router.HelpersTest do
  use ExUnit.Case, async: true
  use ConnHelper

  alias Phoenix.Router.Helpers

  ## Unit tests

  defmodule HTTPSRouter do
    def config(:https), do: [port: 443]
    def config(:url), do: [host: "example.com"]
  end

  defmodule HTTPRouter do
    def config(:https), do: false
    def config(:http), do: [port: 80]
    def config(:url), do: [host: "example.com"]
  end

  defmodule URLRouter do
    def config(:https), do: false
    def config(:http), do: false
    def config(:url), do: [host: "example.com", port: 678, scheme: "random"]
  end

  test "generates url" do
    assert Helpers.url(URLRouter) == "random://example.com:678"
    assert Helpers.url(HTTPRouter) == "http://example.com"
    assert Helpers.url(HTTPSRouter) == "https://example.com"
  end

  test "defhelper with :identifiers" do
    route = build("GET", "/foo/:bar", nil, Hello, :world, "hello_world", [])

    assert extract_defhelper(route, 0) == String.strip """
    def(hello_world_path(:world, bar)) do
      hello_world_path(:world, bar, [])
    end
    """

    assert extract_defhelper(route, 1) == String.strip """
    def(hello_world_path(:world, bar, params)) do
      to_path(("" <> "/foo") <> "/" <> to_string(bar), params, ["bar"])
    end
    """
  end

  test "defhelper with *identifiers" do
    route = build("GET", "/foo/*bar", nil, Hello, :world, "hello_world", [])

    assert extract_defhelper(route, 0) == String.strip """
    def(hello_world_path(:world, bar)) do
      hello_world_path(:world, bar, [])
    end
    """

    assert extract_defhelper(route, 1) == String.strip """
    def(hello_world_path(:world, bar, params)) do
      to_path(("" <> "/foo") <> "/" <> Enum.join(bar, "/"), params, ["bar"])
    end
    """
  end

  defp build(verb, path, host, controller, action, helper, pipe_through) do
    Phoenix.Router.Route.build(verb, path, host, controller, action, helper, pipe_through)
  end

  defp extract_defhelper(route, pos) do
    {:__block__, _, block} = Helpers.defhelper(route)
    Enum.at(block, pos) |> Macro.to_string()
  end

  ## Integration tests

  defmodule Router do
    use Phoenix.Router

    get "/posts/top", PostController, :top, as: :top
    get "/posts/:id", PostController, :show
    get "/posts/file/*file", PostController, :file
    get "/posts/skip", PostController, :skip, as: nil

    resources "/users", UserController do
      resources "/comments", CommentController do
        resources "/files", FileController
      end
    end

    resources "/files", FileController

    scope "/admin", alias: Admin do
      resources "/messages", MessageController
    end

    scope "/admin/new", alias: Admin, as: "admin" do
      resources "/messages", MessageController
    end

    get "/", PageController, :root, as: :page
  end

  setup_all do
    Application.put_env(:phoenix, Router, url: [host: "example.com"],
                        http: false, https: false)
    Router.start()
    on_exit &Router.stop/0
    :ok
  end

  alias Router.Helpers

  test "top-level named route" do
    assert Helpers.post_path(:show, 5) == "/posts/5"
    assert Helpers.post_path(:show, 5, []) == "/posts/5"
    assert Helpers.post_path(:show, 5, id: 5) == "/posts/5"
    assert Helpers.post_path(:show, 5, %{"id" => 5}) == "/posts/5"

    assert Helpers.post_path(:file, ["foo", "bar"]) == "/posts/file/foo/bar"
    assert Helpers.post_path(:file, ["foo", "bar"], []) == "/posts/file/foo/bar"

    assert Helpers.top_path(:top) == "/posts/top"
    assert Helpers.top_path(:top, id: 5) == "/posts/top?id=5"
    assert Helpers.top_path(:top, %{"id" => 5}) == "/posts/top?id=5"

    assert Helpers.page_path(:root) == "/"

    assert_raise UndefinedFunctionError, fn ->
      Helpers.post_path(:skip)
    end
  end

  test "resources generates named routes for :index, :edit, :show, :new" do
    assert Helpers.user_path(:index, []) == "/users"
    assert Helpers.user_path(:index) == "/users"
    assert Helpers.user_path(:edit, 123, []) == "/users/123/edit"
    assert Helpers.user_path(:edit, 123) == "/users/123/edit"
    assert Helpers.user_path(:show, 123, []) == "/users/123"
    assert Helpers.user_path(:show, 123) == "/users/123"
    assert Helpers.user_path(:new, []) == "/users/new"
    assert Helpers.user_path(:new) == "/users/new"
  end

  test "resources generates named routes for :create, :update, :delete" do
    assert Helpers.message_path(:create, []) == "/admin/messages"
    assert Helpers.message_path(:create) == "/admin/messages"

    assert Helpers.message_path(:update, 1, []) == "/admin/messages/1"
    assert Helpers.message_path(:update, 1) == "/admin/messages/1"

    assert Helpers.message_path(:destroy, 1, []) == "/admin/messages/1"
    assert Helpers.message_path(:destroy, 1) == "/admin/messages/1"
  end

  test "1-Level nested resources generates nested named routes for :index, :edit, :show, :new" do
    assert Helpers.user_comment_path(:index, 99, []) == "/users/99/comments"
    assert Helpers.user_comment_path(:index, 99) == "/users/99/comments"
    assert Helpers.user_comment_path(:edit, 88, 2, []) == "/users/88/comments/2/edit"
    assert Helpers.user_comment_path(:edit, 88, 2) == "/users/88/comments/2/edit"
    assert Helpers.user_comment_path(:show, 123, 2, []) == "/users/123/comments/2"
    assert Helpers.user_comment_path(:show, 123, 2) == "/users/123/comments/2"
    assert Helpers.user_comment_path(:new, 88, []) == "/users/88/comments/new"
    assert Helpers.user_comment_path(:new, 88) == "/users/88/comments/new"
  end

  test "2-Level nested resources generates nested named routes for :index, :edit, :show, :new" do
    assert Helpers.user_comment_file_path(:index, 99, 1, []) ==
      "/users/99/comments/1/files"
    assert Helpers.user_comment_file_path(:index, 99, 1) ==
      "/users/99/comments/1/files"

    assert Helpers.user_comment_file_path(:edit, 88, 1, 2, []) ==
      "/users/88/comments/1/files/2/edit"
    assert Helpers.user_comment_file_path(:edit, 88, 1, 2) ==
      "/users/88/comments/1/files/2/edit"

    assert Helpers.user_comment_file_path(:show, 123, 1, 2, []) ==
      "/users/123/comments/1/files/2"
    assert Helpers.user_comment_file_path(:show, 123, 1, 2) ==
      "/users/123/comments/1/files/2"

    assert Helpers.user_comment_file_path(:new, 88, 1, []) ==
      "/users/88/comments/1/files/new"
    assert Helpers.user_comment_file_path(:new, 88, 1) ==
      "/users/88/comments/1/files/new"
  end

  test "resources without block generates named routes for :index, :edit, :show, :new" do
    assert Helpers.file_path(:index, []) == "/files"
    assert Helpers.file_path(:index) == "/files"
    assert Helpers.file_path(:edit, 123, []) == "/files/123/edit"
    assert Helpers.file_path(:edit, 123) == "/files/123/edit"
    assert Helpers.file_path(:show, 123, []) == "/files/123"
    assert Helpers.file_path(:show, 123) == "/files/123"
    assert Helpers.file_path(:new, []) == "/files/new"
    assert Helpers.file_path(:new) == "/files/new"
  end

  test "scoped route helpers generated named routes with :path, and :alias options" do
    assert Helpers.message_path(:index, []) == "/admin/messages"
    assert Helpers.message_path(:index) == "/admin/messages"
    assert Helpers.message_path(:show, 1, []) == "/admin/messages/1"
    assert Helpers.message_path(:show, 1) == "/admin/messages/1"
  end

  test "scoped route helpers generated named routes with :path, :alias, and :helper options" do
    assert Helpers.admin_message_path(:index, []) == "/admin/new/messages"
    assert Helpers.admin_message_path(:index) == "/admin/new/messages"
    assert Helpers.admin_message_path(:show, 1, []) == "/admin/new/messages/1"
    assert Helpers.admin_message_path(:show, 1) == "/admin/new/messages/1"
  end

  test "helpers module generates a url helper" do
    assert Helpers.url("/foo/bar") == "http://example.com/foo/bar"
  end
end
