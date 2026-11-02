namespace PrabinBhusal.ExplainResolve;

using System.Email;
using System.Utilities;

// Saves drafted emails in the outbox or opens them in the editor. Nothing here sends an email; the user does.
codeunit 58205 "EXR Email Draft"
{
    Access = Internal;

    var
        SubjectReferenceTok: Label '%1 %2', Locked = true;
        WholeReferenceTok: Label '(?<![A-Z0-9])%1(?![A-Z0-9])', Locked = true;

    // False when no email account exists: the text stays on the run and can be opened from there later.
    procedure SaveDraft(ExrRun: Record "EXR Run"; RelatedTableNo: Integer; RelatedSystemId: Guid): Boolean
    var
        EmailAccount: Codeunit "Email Account";
        Email: Codeunit Email;
        EmailMessage: Codeunit "Email Message";
    begin
        if not EmailAccount.IsAnyAccountRegistered() then
            exit(false);
        CreateMessage(ExrRun, EmailMessage);
        if RelatedTableNo <> 0 then
            Email.AddRelation(EmailMessage, RelatedTableNo, RelatedSystemId, Enum::"Email Relation Type"::"Related Entity", Enum::"Email Relation Origin"::"Compose Context");
        Email.SaveAsDraft(EmailMessage);
        exit(true);
    end;

    procedure OpenInEditor(ExrRun: Record "EXR Run")
    var
        Email: Codeunit Email;
        EmailMessage: Codeunit "Email Message";
    begin
        CreateMessage(ExrRun, EmailMessage);
        Email.OpenInEditor(EmailMessage);
    end;

    // One email per finding, related to the record the finding is about (the customer), so it shows in its email history.
    // var, so a temporary finding is read from its own buffer
    procedure SaveFindingDraft(var Finding: Record "EXR Finding"): Boolean
    var
        EmailAccount: Codeunit "Email Account";
        Email: Codeunit Email;
        EmailMessage: Codeunit "Email Message";
    begin
        if not EmailAccount.IsAnyAccountRegistered() then
            exit(false);
        CreateFindingMessage(Finding, EmailMessage);
        Email.SaveAsDraft(EmailMessage);
        exit(true);
    end;

    procedure OpenFindingInEditor(var Finding: Record "EXR Finding")
    var
        Email: Codeunit Email;
        EmailMessage: Codeunit "Email Message";
    begin
        CreateFindingMessage(Finding, EmailMessage);
        Email.OpenInEditor(EmailMessage);
    end;

    // The subject always carries the reference, such as the vendor invoice number, even when the model or the user left it out.
    // An empty subject stays empty (no email), and a long subject is shortened so the reference still fits in MaxLength.
    procedure SubjectWithReference(Subject: Text; Reference: Text; MaxLength: Integer): Text
    var
        Regex: Codeunit Regex;
    begin
        if (Subject = '') or (Reference = '') then
            exit(CopyStr(Subject, 1, MaxLength));
        // the whole reference, not part of a longer number: 44 is not found in 1,440.00
        if Regex.IsMatch(UpperCase(Subject), StrSubstNo(WholeReferenceTok, Regex.Escape(UpperCase(Reference)))) then
            exit(CopyStr(Subject, 1, MaxLength));
        if StrLen(Reference) >= MaxLength then
            exit(CopyStr(Reference, 1, MaxLength));
        exit(StrSubstNo(SubjectReferenceTok, CopyStr(Subject, 1, MaxLength - StrLen(Reference) - 1).TrimEnd(), Reference).Trim());
    end;

    local procedure CreateMessage(ExrRun: Record "EXR Run"; var EmailMessage: Codeunit "Email Message")
    var
        Email: Codeunit Email;
    begin
        EmailMessage.Create(ExrRun."Email To", ExrRun."Email Subject", ToHtml(ExrRun.GetEmailBody()), true);
        // a run over a selection, such as Plan collections, has no single source record
        if not IsNullGuid(ExrRun."Source System Id") then
            Email.AddRelation(EmailMessage, ExrRun."Source Table No.", ExrRun."Source System Id", Enum::"Email Relation Type"::"Primary Source", Enum::"Email Relation Origin"::"Compose Context");
    end;

    local procedure CreateFindingMessage(var Finding: Record "EXR Finding"; var EmailMessage: Codeunit "Email Message")
    var
        Email: Codeunit Email;
    begin
        EmailMessage.Create(Finding."Email To", Finding."Email Subject", ToHtml(Finding.GetEmailBody()), true);
        if not IsNullGuid(Finding."Source System Id") then
            Email.AddRelation(EmailMessage, Finding."Source Record ID".TableNo(), Finding."Source System Id", Enum::"Email Relation Type"::"Primary Source", Enum::"Email Relation Origin"::"Compose Context");
    end;

    // The body is plain text; the editor shows HTML, so escape it and keep the line breaks.
    local procedure ToHtml(PlainText: Text): Text
    var
        CarriageReturn: Char;
        LineFeed: Char;
    begin
        CarriageReturn := 13;
        LineFeed := 10;
        exit(PlainText.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace(Format(CarriageReturn), '').Replace(Format(LineFeed), '<br>'));
    end;
}
