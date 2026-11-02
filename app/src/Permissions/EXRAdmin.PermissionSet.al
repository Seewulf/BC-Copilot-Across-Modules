namespace PrabinBhusal.ExplainResolve;

// Everything a user has, plus maintaining the setup and the API key, running Test Connection and deleting runs.
permissionset 58201 "EXR ADMIN"
{
    Caption = 'Explain and Resolve - Admin';
    Assignable = true;
    IncludedPermissionSets = "EXR USER";

    Permissions =
        tabledata "EXR Setup" = RIMD,
        tabledata "EXR Run" = RIMD,
        tabledata "EXR Finding" = RIMD,
        page "EXR Setup" = X,
        codeunit "EXR Connection Test" = X;
}
