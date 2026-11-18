defmodule CauldronNative.Device.AnswerTest do
  use ExUnit.Case, async: true

  alias CauldronNative.Device.{Answer, Request}

  defp id(tag), do: Request.id(tag)

  test "answers carry the request's tag and the platform's words as atoms" do
    tag = {:permission, :camera}

    assert Answer.decode(~s({"id":"#{id(tag)}","status":"ok","value":"granted"})) ==
             {:device, tag, {:ok, :granted}}

    assert Answer.decode(~s({"id":"#{id(:photo)}","status":"error","value":"not_declared"})) ==
             {:device, :photo, {:error, :not_declared}}

    assert Answer.decode(~s({"id":"#{id(:photo)}","status":"cancelled"})) ==
             {:device, :photo, :cancelled}

    assert Answer.decode(~s({"id":"#{id(:picked)}","status":"ok","value":["/a.jpg"]})) ==
             {:device, :picked, {:ok, ["/a.jpg"]}}
  end
end
