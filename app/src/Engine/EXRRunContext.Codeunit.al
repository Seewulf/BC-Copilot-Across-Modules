namespace PrabinBhusal.ExplainResolve;

using Microsoft.Finance.GeneralLedger.Setup;
using System.Utilities;

// Facts of the current run (token -> formatted value) and the wrapper for untrusted text. Cleared at the start of every run.
codeunit 58203 "EXR Run Context"
{
    SingleInstance = true;

    var
        FactValues: Dictionary of [Text, Text];
        FactCaptions: Dictionary of [Text, Text];
        FactOwners: Dictionary of [Text, Text];
        FactTokens: List of [Text];
        DateTokens: List of [Text];
        ContextNames: List of [Text];
        ContextValues: List of [Text];
        ContextOwners: List of [Text];
        CurrencyCodes: List of [Text];
        FindingReferences: Dictionary of [Text, Text];
        LcyCode: Code[10];
        LcyLoaded: Boolean;
        EmailReferenceText: Text;
        TokenTok: Label '{F%1}', Locked = true;
        // the code before or after a number, not inside a word such as INV4471
        CurrencyFigureTok: Label '(?<![A-Z])(%1)\s?\d|\d\s?(%1)(?![A-Z])', Locked = true;
        UntrustedTok: Label '<untrusted>%1</untrusted>', Locked = true;
        AmountTok: Label '%1 %2', Locked = true;
        PercentTok: Label '%', Locked = true;
        AmountFormatTok: Label '<Precision,2:2><Standard Format,0>', Locked = true;
        QuantityFormatTok: Label '<Precision,0:5><Standard Format,0>', Locked = true;
        PercentFormatTok: Label '<Precision,0:2><Standard Format,0>', Locked = true;
        DateFormatTok: Label '<Day> <Month Text> <Year4>', Locked = true;
        TypeCodes: List of [Text];

    procedure StartRun()
    begin
        Clear(FactValues);
        Clear(FactCaptions);
        Clear(FactOwners);
        Clear(FactTokens);
        Clear(DateTokens);
        Clear(ContextNames);
        Clear(ContextValues);
        Clear(ContextOwners);
        Clear(CurrencyCodes);
        Clear(FindingReferences);
        Clear(TypeCodes);
        EmailReferenceText := '';
        LcyLoaded := false;
        LoadLcy();
        AddCurrency(LcyCode);
    end;

    // A currency of the document. With the local currency it makes up the codes the stray-figure check looks for.
    procedure AddCurrency(CurrencyCode: Code[10])
    begin
        if (CurrencyCode <> '') and not CurrencyCodes.Contains(CurrencyCode) then
            CurrencyCodes.Add(CurrencyCode);
    end;

    // Matches an amount written with one of the run's currency codes, such as GBP 150 or 150 GBP. Empty when there is none.
    procedure CurrencyFigurePattern(): Text
    var
        Regex: Codeunit Regex;
        CurrencyCode: Text;
        Alternatives: Text;
    begin
        foreach CurrencyCode in CurrencyCodes do begin
            if Alternatives <> '' then
                Alternatives += '|';
            Alternatives += Regex.Escape(CurrencyCode);
        end;
        if Alternatives = '' then
            exit('');
        exit(StrSubstNo(CurrencyFigureTok, Alternatives));
    end;

    // Owner is the finding key, or empty for facts about the whole document. Each Add returns the token, for example {F3}.
    procedure AddAmount(Owner: Text; FactCaption: Text; Amount: Decimal): Text
    begin
        exit(AddFact(Owner, FactCaption, FormatAmount(Amount)));
    end;

    procedure AddQuantity(Owner: Text; FactCaption: Text; Quantity: Decimal): Text
    begin
        exit(AddFact(Owner, FactCaption, FormatQuantity(Quantity)));
    end;

    procedure AddPercent(Owner: Text; FactCaption: Text; Percent: Decimal): Text
    begin
        exit(AddFact(Owner, FactCaption, FormatPercent(Percent)));
    end;

    procedure AddCount(Owner: Text; FactCaption: Text; Number: Integer): Text
    begin
        exit(AddFact(Owner, FactCaption, Format(Number, 0, 9)));
    end;

    procedure AddDate(Owner: Text; FactCaption: Text; FactDate: Date) Token: Text
    begin
        Token := AddFact(Owner, FactCaption, FormatDate(FactDate));
        DateTokens.Add(Token);
    end;

    // A phrase that AL built with the right singular or plural, such as "1 invoice" or "3 of the 4 lines checked have no differences".
    procedure AddPhrase(Owner: Text; FactCaption: Text; Phrase: Text): Text
    begin
        exit(AddFact(Owner, FactCaption, Phrase));
    end;

    // Text from records or from the user: always sent wrapped.
    procedure AddContext(Name: Text; UntrustedValue: Text)
    begin
        AddFindingContext('', Name, UntrustedValue);
    end;

    // Text about one finding, such as the vendor invoice numbers of a possible duplicate. Sent wrapped, with that finding.
    procedure AddFindingContext(Owner: Text; Name: Text; UntrustedValue: Text)
    begin
        ContextOwners.Add(Owner);
        ContextNames.Add(Name);
        ContextValues.Add(WrapUntrusted(UntrustedValue));
    end;

    // What the user reads where the model wrote a finding key. The first reference wins: a capability can give a short one
    // while it finds the differences, and the engine adds the subject for every other finding.
    procedure AddFindingReference(FindingKey: Text; Reference: Text)
    begin
        if not FindingReferences.ContainsKey(FindingKey) then
            FindingReferences.Add(FindingKey, Reference);
    end;

    // A type code of the capability, such as BANK or NOT_RECEIVED, which the user never sees either; every code, found in this run or not.
    procedure AddTypeCode(TypeCode: Text)
    begin
        if (TypeCode <> '') and not TypeCodes.Contains(TypeCode) then
            TypeCodes.Add(TypeCode);
    end;

    procedure FindingTypeCodes(): List of [Text]
    begin
        exit(TypeCodes);
    end;

    procedure FindingKeys(): List of [Text]
    begin
        exit(FindingReferences.Keys());
    end;

    procedure FindingReference(FindingKey: Text): Text
    begin
        exit(FindingReferences.Get(FindingKey));
    end;

    // A reference that the email subject must contain, such as the vendor invoice number. AL adds it when the model leaves it out.
    procedure SetEmailReference(Reference: Text)
    begin
        EmailReferenceText := Reference;
    end;

    procedure EmailReference(): Text
    begin
        exit(EmailReferenceText);
    end;

    // Tags mark the text as data. Escaping & < > means the text cannot close the tag itself.
    procedure WrapUntrusted(Value: Text): Text
    begin
        exit(StrSubstNo(UntrustedTok, Value.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;')));
    end;

    procedure TryGetFact(Token: Text; var Value: Text): Boolean
    begin
        exit(FactValues.Get(Token, Value));
    end;

    // A date fact of this owner only, for an email to that party: never another owner's figure or an internal amount.
    procedure TryGetDateFactOf(Token: Text; Owner: Text; var Value: Text): Boolean
    var
        TokenOwner: Text;
    begin
        if not DateTokens.Contains(Token) then
            exit(false);
        if not FactOwners.Get(Token, TokenOwner) then
            exit(false);
        if TokenOwner <> Owner then
            exit(false);
        exit(FactValues.Get(Token, Value));
    end;

    procedure FormatAmount(Amount: Decimal): Text
    begin
        LoadLcy();
        exit(FormatCurrencyAmount(Amount, LcyCode));
    end;

    // An amount in the currency it was posted in, such as a customer's open invoice in EUR. Blank means local currency.
    procedure FormatCurrencyAmount(Amount: Decimal; CurrencyCode: Code[10]): Text
    begin
        if CurrencyCode = '' then begin
            LoadLcy();
            CurrencyCode := LcyCode;
        end;
        if CurrencyCode = '' then
            exit(Format(Amount, 0, AmountFormatTok));
        exit(StrSubstNo(AmountTok, CurrencyCode, Format(Amount, 0, AmountFormatTok)));
    end;

    procedure FormatQuantity(Quantity: Decimal): Text
    begin
        exit(Format(Quantity, 0, QuantityFormatTok));
    end;

    procedure FormatPercent(Percent: Decimal): Text
    begin
        exit(Format(Round(Percent, 0.01), 0, PercentFormatTok) + PercentTok);
    end;

    // Written out, so it reads the same in every email: 12 August 2026.
    procedure FormatDate(FactDate: Date): Text
    begin
        exit(Format(FactDate, 0, DateFormatTok));
    end;

    // Picks the singular or the plural text, for example '%1 invoice' or '%1 invoices'.
    procedure CountPhrase(Number: Integer; SingularText: Text; PluralText: Text): Text
    begin
        if Number = 1 then
            exit(StrSubstNo(SingularText, Number));
        exit(StrSubstNo(PluralText, Number));
    end;

    procedure ContextJson(): JsonObject
    begin
        exit(FindingContextJson(''));
    end;

    // Empty owner: the context of the whole run.
    procedure FindingContextJson(Owner: Text) Context: JsonObject
    var
        Index: Integer;
    begin
        for Index := 1 to ContextNames.Count() do
            if ContextOwners.Get(Index) = Owner then
                Context.Add(ContextNames.Get(Index), ContextValues.Get(Index));
    end;

    // {"{F3}": {"caption": "invoiced quantity", "value": "10"}, ...} for one owner.
    procedure FactsJson(Owner: Text) Facts: JsonObject
    var
        Token: Text;
    begin
        foreach Token in FactTokens do
            if FactOwners.Get(Token) = Owner then
                Facts.Add(Token, FactJson(Token));
    end;

    local procedure FactJson(Token: Text) Fact: JsonObject
    begin
        Fact.Add('caption', FactCaptions.Get(Token));
        Fact.Add('value', FactValues.Get(Token));
    end;

    local procedure AddFact(Owner: Text; FactCaption: Text; Value: Text) Token: Text
    begin
        Token := StrSubstNo(TokenTok, FactTokens.Count() + 1);
        FactTokens.Add(Token);
        FactValues.Add(Token, Value);
        FactCaptions.Add(Token, FactCaption);
        FactOwners.Add(Token, Owner);
    end;

    // Also outside a run, for example when Keep it renders an email table.
    local procedure LoadLcy()
    var
        GeneralLedgerSetup: Record "General Ledger Setup";
    begin
        if LcyLoaded then
            exit;
        LcyCode := '';
        GeneralLedgerSetup.SetLoadFields("LCY Code");
        if GeneralLedgerSetup.Get() then
            LcyCode := GeneralLedgerSetup."LCY Code";
        LcyLoaded := true;
    end;
}
