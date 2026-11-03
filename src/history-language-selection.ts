export interface LanguagePair { sourceLanguage: string; targetLanguage: string }

// A history entry contains resolved languages, not the user's automatic/manual
// preference. Its temporary selection belongs only to the replayed source.
export class HistoryLanguageSelection {
  private beforeReplay: LanguagePair | null = null;

  replay(current: LanguagePair, historical: LanguagePair): LanguagePair {
    this.beforeReplay ??= { ...current };
    return { sourceLanguage: historical.sourceLanguage, targetLanguage: historical.targetLanguage };
  }

  newInput(current: LanguagePair): LanguagePair {
    const preferred = this.beforeReplay ?? current;
    this.beforeReplay = null;
    return { ...preferred };
  }

  choose(): void { this.beforeReplay = null; }
}
