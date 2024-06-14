{
  lib,
  nixvimTypes,
  nixvimUtils,
}:
with lib;
with nixvimUtils;
let
  # Render a plugin default string
  pluginDefaultText =
    let
      # Assume a string `pluginDefault` is already formatted as intended,
      # TODO: remove this behavior so we can quote strings properly
      # historically strings were the only type accepted by mkDesc.
      legacyRenderOptionValue =
        v:
        literalExpression (
          if isString v then
            v
          else
            generators.toPretty {
              allowPrettyValues = true;
              multiline = true;
            } v
        );
    in
    {
      # plugin default: any value or literal expression
      pluginDefault,
      # nix option default value, used if `nixDefaultText` is missing
      default ? null,
      # nix option default string or literal expression
      defaultText ? (options.renderOptionValue default) // {
        __lang = "nix";
      },
      ...
    }:
    let
      # Only add `__lang` if `pluginDefault` is not already a literal type
      pluginDefaultText =
        if pluginDefault ? _type && pluginDefault ? text then
          pluginDefault
        else
          (legacyRenderOptionValue pluginDefault) // { __lang = "nix"; };

      # Format text using markdown code block or inline code
      # Handle `v` being a literalExpression or literalMD type
      toMD =
        v:
        let
          value = options.renderOptionValue v;
          multiline = hasInfix "\n" value.text;
          lang = value.__lang or ""; # `__lang` is added internally when parsed in argument defaults
        in
        if value._type == "literalMD" then
          if multiline then "\n${value.text}" else " ${value.text}"
        else if multiline then
          "\n```${lang}\n${value.text}\n```"
        else
          " `${value.text}`";
    in
    literalMD ''
      ${toMD defaultText}

      _Plugin default:_${toMD pluginDefaultText}
    '';

  # Convert args into normal `mkOption`-style arguments, i.e. merge `pluginDefault` into `defaultText`.
  #
  # - `defaultText` is only set if `args` contains `pluginDefault`.
  # - `pluginDefault` is removed from the resulting args.
  # - All other args are untouched.
  processNixvimArgs =
    args:
    (removeAttrs args [ "pluginDefault" ])
    // (optionalAttrs (args ? pluginDefault) { defaultText = pluginDefaultText args; });
in
rec {
  inherit pluginDefaultText;

  # Creates an option with a nullable type that defaults to null.
  mkNullOrOption' =
    {
      type,
      default ? null,
      ...
    }@args:
    lib.mkOption (
      (processNixvimArgs args)
      // {
        type = lib.types.nullOr type;
        inherit default;
      }
    );
  mkNullOrOption = type: description: mkNullOrOption' { inherit type description; };

  mkCompositeOption' =
    { options, ... }@args:
    mkNullOrOption' (
      (filterAttrs (n: _: n != "options") args) // { type = types.submodule { inherit options; }; }
    );
  mkCompositeOption = description: options: mkCompositeOption' { inherit description options; };

  mkNullOrStr' = args: mkNullOrOption' (args // { type = with nixvimTypes; maybeRaw str; });
  mkNullOrStr = description: mkNullOrStr' { inherit description; };

  mkNullOrLua' =
    args:
    mkNullOrOption' (
      args
      // {
        type = nixvimTypes.strLua;
        apply = mkRaw;
      }
    );
  mkNullOrLua = description: mkNullOrLua' { inherit description; };

  mkNullOrLuaFn' =
    args:
    mkNullOrOption' (
      args
      // {
        type = nixvimTypes.strLuaFn;
        apply = mkRaw;
      }
    );
  mkNullOrLuaFn = description: mkNullOrLua' { inherit description; };

  mkNullOrStrLuaOr' =
    { type, ... }@args:
    mkNullOrOption' (
      args
      // {
        type = with nixvimTypes; either strLua type;
        apply = v: if isString v then mkRaw v else v;
      }
    );
  mkNullOrStrLuaOr = type: description: mkNullOrStrLuaOr' { inherit type description; };

  mkNullOrStrLuaFnOr' =
    { type, ... }@args:
    mkNullOrOption' (
      args
      // {
        type = with nixvimTypes; either strLuaFn type;
        apply = v: if isString v then mkRaw v else v;
      }
    );
  mkNullOrStrLuaFnOr = type: description: mkNullOrStrLuaFnOr' { inherit type description; };

  defaultNullOpts =
    let
      # Ensures that default is null and defaultText is not set
      convertArgs =
        args:
        assert
          args ? default
          -> abort "defaultNullOpts: unexpected argument `default`. Did you mean `pluginDefault`?";
        assert
          args ? defaultText
          -> abort "defaultNullOpts: unexpected argument `defaultText`. Did you mean `pluginDefault`?";
        args // { default = null; };
    in
    rec {
      # TODO: removed 2024-06-14; remove stub 2024-09-01
      mkDesc = abort "mkDesc has been removed. Use the `pluginDefault` argument or `helpers.pluginDefaultText`.";

      mkNullable' = args: mkNullOrOption' (convertArgs args);
      mkNullable =
        type: pluginDefault: description:
        mkNullable' { inherit type pluginDefault description; };

      mkNullableWithRaw' =
        { type, ... }@args: mkNullable' (args // { type = nixvimTypes.maybeRaw type; });
      mkNullableWithRaw =
        type: pluginDefault: description:
        mkNullableWithRaw' { inherit type pluginDefault description; };

      mkStrLuaOr' = args: mkNullOrStrLuaOr' (convertArgs args);
      mkStrLuaOr =
        type: pluginDefault: description:
        mkStrLuaOr' { inherit type pluginDefault description; };

      mkStrLuaFnOr' = args: mkNullOrStrLuaFnOr' (convertArgs args);
      mkStrLuaFnOr =
        type: pluginDefault: description:
        mkStrLuaFnOr' { inherit type pluginDefault description; };

      mkLua' = args: mkNullOrLua' (convertArgs args);
      mkLua = pluginDefault: description: mkLua' { inherit pluginDefault description; };

      mkLuaFn' = args: mkNullOrLuaFn' (convertArgs args);
      mkLuaFn = pluginDefault: description: mkLuaFn' { inherit pluginDefault description; };

      mkNum' = args: mkNullableWithRaw' (args // { type = types.number; });
      mkNum = pluginDefault: description: mkNum' { inherit pluginDefault description; };
      mkInt' = args: mkNullableWithRaw' (args // { type = types.int; });
      mkInt = pluginDefault: description: mkNum' { inherit pluginDefault description; };
      # Positive: >0
      mkPositiveInt' = args: mkNullableWithRaw' (args // { type = types.ints.positive; });
      mkPositiveInt = pluginDefault: description: mkPositiveInt' { inherit pluginDefault description; };
      # Unsigned: >=0
      mkUnsignedInt' = args: mkNullableWithRaw' (args // { type = types.ints.unsigned; });
      mkUnsignedInt = pluginDefault: description: mkUnsignedInt' { inherit pluginDefault description; };
      mkBool' = args: mkNullableWithRaw' (args // { type = types.bool; });
      mkBool = pluginDefault: description: mkBool' { inherit pluginDefault description; };
      mkStr' =
        args:
        mkNullableWithRaw' (
          args
          // {
            type = types.str;
          }
          # TODO we should remove this once `mkDesc` no longer has a special case
          // (optionalAttrs (args ? pluginDefault) {
            pluginDefault = generators.toPretty { } args.pluginDefault;
          })
        );
      mkStr = pluginDefault: description: mkStr' { inherit pluginDefault description; };

      mkAttributeSet' = args: mkNullable' (args // { type = nixvimTypes.attrs; });
      mkAttributeSet = pluginDefault: description: mkAttributeSet' { inherit pluginDefault description; };

      mkListOf' =
        { type, ... }@args: mkNullable' (args // { type = with nixvimTypes; listOf (maybeRaw type); });
      mkListOf =
        type: pluginDefault: description:
        mkListOf' { inherit type pluginDefault description; };

      mkAttrsOf' =
        { type, ... }@args: mkNullable' (args // { type = with nixvimTypes; attrsOf (maybeRaw type); });
      mkAttrsOf =
        type: pluginDefault: description:
        mkAttrsOf' { inherit type pluginDefault description; };

      mkEnum' =
        { values, ... }@args:
        # `values` is a list. If `pluginDefault` is present, then it is either null or one of `values`
        assert isList values;
        assert args ? pluginDefault -> (args.pluginDefault == null || elem args.pluginDefault values);
        mkNullableWithRaw' (
          (filterAttrs (n: v: n != "values") args)
          // {
            type = types.enum values;
          }
          # TODO we should remove this once `mkDesc` no longer has a special case
          // (optionalAttrs (args ? pluginDefault) {
            pluginDefault = generators.toPretty { } args.pluginDefault;
          })
        );
      mkEnum =
        values: pluginDefault: description:
        mkEnum' { inherit values pluginDefault description; };
      mkEnumFirstDefault =
        values: description:
        mkEnum' {
          inherit values description;
          pluginDefault = head values;
        };

      mkBorder' =
        {
          name,
          description ? "",
          ...
        }@args:
        mkNullableWithRaw' (
          (filterAttrs (n: v: n != "name") args)
          // {
            type = nixvimTypes.border;
            description = concatStringsSep "\n" (
              (optional (description != "") description)
              ++ [
                "Defines the border to use for ${name}."
                "Accepts same border values as `nvim_open_win()`. See `:help nvim_open_win()` for more info."
              ]
            );
          }
        );
      mkBorder =
        pluginDefault: name: description:
        mkBorder' { inherit pluginDefault name description; };

      mkSeverity' =
        args:
        mkNullOrOption' (
          args
          // {
            type =
              with types;
              either ints.unsigned (enum [
                "error"
                "warn"
                "info"
                "hint"
              ]);
            apply = mapNullable (
              value: if isInt value then value else mkRaw "vim.diagnostic.severity.${strings.toUpper value}"
            );
          }
        );
      mkSeverity = pluginDefault: description: mkSeverity' { inherit pluginDefault description; };

      mkLogLevel' =
        args:
        mkNullOrOption' (
          args
          // {
            type = with nixvimTypes; either ints.unsigned logLevel;
            apply = mapNullable (
              value: if isInt value then value else mkRaw "vim.log.levels.${strings.toUpper value}"
            );
          }
        );
      mkLogLevel = pluginDefault: description: mkLogLevel' { inherit pluginDefault description; };

      mkHighlight' =
        {
          description ? "Highlight settings.",
          ...
        }@args:
        mkNullable' (
          args
          // {
            type = nixvimTypes.highlight;
            inherit description;
          }
        );
      # FIXME `name` argument is ignored
      # TODO deprecate in favor of `mkHighlight'`?
      mkHighlight =
        pluginDefault: name: description:
        mkHighlight' (
          {
            inherit pluginDefault;
          }
          // (optionalAttrs (description != null && description != "") { inherit description; })
        );
    };

  mkPackageOption =
    args:
    # A default package is required
    assert args ? default;
    # `name` must be present if `description` is missing
    assert (!args ? description) -> args ? name;
    mkNullOrOption' (
      (filterAttrs (n: _: n != "name") args)
      // {
        type = types.package;
        description =
          args.description or ''
            Which package to use for `${args.name}`.
            Set to `null` to disable its automatic installation.
          '';
      }
    );

  mkPluginPackageOption =
    name: default:
    mkOption {
      type = types.package;
      inherit default;
      description = "Which package to use for the ${name} plugin.";
    };

  mkSettingsOption =
    {
      options ? { },
      description,
      example ? null,
    }:
    mkOption {
      type =
        with types;
        submodule {
          freeformType = attrsOf anything;
          inherit options;
        };
      default = { };
      inherit description;
      example =
        if example == null then
          {
            foo_bar = 42;
            hostname = "localhost:8080";
            callback.__raw = ''
              function()
                print('nixvim')
              end
            '';
          }
        else
          example;
    };
}
