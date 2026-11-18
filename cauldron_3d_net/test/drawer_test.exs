defmodule Cauldron3D.Net.DrawerTest do
  use ExUnit.Case, async: true

  alias Cauldron3D.Net.{Drawer, Outbox, RemoteScene}
  alias Cauldron3D.Scene.{Handle, Instance, Material, Mesh, Stream, Target}

  defp gpu(target, nil, _size, _aspect) do
    mesh = Target.mesh(target, Mesh.cube(1.0))
    material = Target.material(target, %Material{})
    {[{:instance, 1, %Instance{mesh: mesh, materials: [material]}}], %{mesh: mesh}}
  end

  defp gpu(_target, cache, _size, _aspect), do: {[{:remove_instance, 1}], cache}

  defp changes(drawer) do
    {drawer, [{"changes", payload}]} = Drawer.draw(drawer, gpu: &gpu/4)
    {drawer, :erlang.binary_to_term(payload)}
  end

  test "a client draws the server's scene with its own handles, the new batches only once it has the rest" do
    {drawer, []} = Drawer.open(Game, params: %{})
    {drawer, first} = changes(drawer)
    {_drawer, second} = changes(drawer)

    {:ok, client} = Outbox.start_link()
    remote = RemoteScene.received(%{}, first)
    %{gpu: draw} = RemoteScene.scene(%{remote: remote})
    {submit, cache} = draw.(client, nil, {640, 360}, 16 / 9)

    [{:mesh, mesh_id, %Mesh{}}, {:material, material_id, %Material{}}] = Outbox.take(client)

    assert [{:instance, 1, %Instance{mesh: %Handle{id: ^mesh_id}, materials: [material]}}] =
             submit

    assert material.id == material_id

    remote = RemoteScene.received(remote, second)
    %{gpu: draw} = RemoteScene.scene(%{remote: remote})
    assert {[{:remove_instance, 1}], _cache} = draw.(client, cache, {640, 360}, 16 / 9)
    assert Outbox.take(client) == []
  end

  test "a browser is sent the stream bytes" do
    {drawer, []} = Drawer.open(Game, params: %{"changes" => "stream"})
    {_drawer, [{"changes", bytes}]} = Drawer.draw(drawer, gpu: &gpu/4)
    {:ok, check} = Outbox.start_link()
    {changes, _cache} = gpu(check, nil, {1, 1}, 1.0)
    Target.submit(check, changes)
    assert bytes == check |> Outbox.take() |> Stream.encode() |> IO.iodata_to_binary()
  end

  test "an upload from another process tells the owner once until it takes" do
    {:ok, outbox} = Outbox.start_link()
    ref = Outbox.ref(outbox)

    Task.await(Task.async(fn -> Outbox.put(outbox, :mesh, Mesh.cube(1.0)) end))
    Task.await(Task.async(fn -> Outbox.put(outbox, :mesh, Mesh.cube(2.0)) end))

    assert_received {Outbox, ^ref, :changed}
    refute_received {Outbox, ^ref, :changed}
    assert [{:mesh, _, _}, {:mesh, _, _}] = Outbox.take(outbox)
  end
end
