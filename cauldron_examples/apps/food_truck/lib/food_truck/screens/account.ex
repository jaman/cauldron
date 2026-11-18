defmodule FoodTruck.Screens.Account do
  @moduledoc """
  The account: the signed-in user's name, help with in-app purchases, and signing in,
  up and out. An account is created with a user name and password and kept for the
  session, as the sample's password accounts are.
  """

  import CauldronNative.UI

  alias FoodTruck.Screens.Social

  @doc "The Account screen for `state.account` and `state.window`."
  @spec page(map()) :: CauldronNative.UI.Node.t()
  def page(state) do
    account = state.account

    screen("Account", [
      form([
        profile(account.user),
        purchases(state.window),
        section(nil, sign(account.user))
      ]),
      sign_up(account),
      alert(
        "Are you sure you want to sign out?",
        [
          button("Sign Out", role: :destructive, on_tap: {:account, :sign_out}),
          button("Cancel", role: :cancel, on_tap: {:account, :keep})
        ],
        shown: account.confirming?,
        on_dismiss: {:account, :keep}
      )
    ])
  end

  @doc "The purchase help screen the account opens."
  @spec support() :: CauldronNative.UI.Node.t()
  def support, do: Social.support_screen()

  defp profile({:signed_in, name}) do
    section(nil, [
      hstack(
        [
          icon(:person,
            ios: "person.fill",
            android: "Person",
            modifiers: [
              font: :large_title,
              bold: true,
              foreground: "#FFFFFF",
              frame: [width: 60, height: 60],
              background: :accent,
              corner_radius: 30
            ]
          ),
          text(name, modifiers: [font: :title3])
        ],
        spacing: 12
      )
    ])
  end

  defp profile(_user), do: nil

  defp purchases(%{mac?: true}),
    do:
      section(nil, [
        hstack([
          text("Purchases"),
          spacer(),
          button("Restore missing purchases", on_tap: {:shop, :restore})
        ])
      ])

  defp purchases(_window),
    do:
      section(nil, [
        label("In-app purchase support",
          icon: :info,
          ios: "questionmark.circle",
          android: "HelpOutline",
          on_tap: :account_support
        )
      ])

  defp sign(nil) do
    [
      hstack([
        text("Use existing account"),
        spacer(),
        button("Sign In", on_tap: {:account, :sign_in})
      ]),
      hstack([
        text("Create new account"),
        spacer(),
        button("Sign Up", on_tap: {:account, :sign_up})
      ])
    ]
  end

  defp sign(_user) do
    [
      button("Sign Out",
        role: :destructive,
        on_tap: {:account, :confirm_sign_out},
        modifiers: [frame: [max_width: :infinity]]
      )
    ]
  end

  defp sign_up(account) do
    form = account.form

    sheet(
      [
        navigation([
          screen(if(form.mode == :sign_in, do: "Sign in", else: "Sign up"), [
            form([
              section(
                if(form.mode == :sign_in, do: "Use your account", else: "Create an account"),
                [
                  text_field("User name",
                    value: form.name,
                    keyboard: :email,
                    capitalize: :none,
                    on_change: {:account_field, :name}
                  ),
                  secure_field("Password",
                    value: form.password,
                    on_change: {:account_field, :password}
                  )
                ]
              )
            ]),
            toolbar([
              button("Cancel", role: :cancel, on_tap: {:account, :cancel}),
              button(if(form.mode == :sign_in, do: "Sign In", else: "Sign Up"),
                style: :prominent,
                disabled: form.name == "" or form.password == "",
                on_tap: {:account, :submit}
              )
            ])
          ])
        ])
      ],
      shown: form.open?,
      on_dismiss: {:account, :cancel}
    )
  end
end
