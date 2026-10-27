"use client";

import React, { createContext, useContext, useState, useEffect, useCallback } from "react";

export type Locale = "en" | "ar" | "zh";

export interface TranslationStrings {
  // App
  appTitle: string;
  appVersion: string;
  // Tabs
  tabDashboard: string;
  tabSoftware: string;
  tabProfiles: string;
  tabUndo: string;
  tabPreview: string;
  // Dashboard
  quickSelect: string;
  allSafe: string;
  safePlusModerate: string;
  allSettings: string;
  noneSettings: string;
  // Safety
  safe: string;
  moderate: string;
  risky: string;
  // Preview
  previewChanges: string;
  confirmApply: string;
  noChanges: string;
  safetyWarnings: string;
  settingConflicts: string;
  createRestorePoint: string;
  restorePointDesc: string;
  // Undo
  undoCenter: string;
  undoAll: string;
  undoBySafety: string;
  // Profiles
  profiles: string;
  saveCurrent: string;
  compare: string;
  // Section Panel
  selectLabel: string;
  filterLabel: string;
  enabled: string;
  // Keyboard
  kbAllSafe: string;
  kbSafeMod: string;
  kbNone: string;
}

const translations: Record<Locale, TranslationStrings> = {
  en: {
    appTitle: "WinPostInstall",
    appVersion: "v4.1.7 Optimizer",
    tabDashboard: "Dashboard",
    tabSoftware: "Software",
    tabProfiles: "Profiles",
    tabUndo: "Undo",
    tabPreview: "Preview",
    quickSelect: "Quick Select",
    allSafe: "All Safe",
    safePlusModerate: "Safe + Moderate",
    allSettings: "All",
    noneSettings: "None",
    safe: "Safe",
    moderate: "Moderate",
    risky: "Risky",
    previewChanges: "Preview Changes",
    confirmApply: "Confirm & Apply",
    noChanges: "No changes selected",
    safetyWarnings: "Safety Warnings",
    settingConflicts: "Setting Conflicts",
    createRestorePoint: "Create System Restore Point before applying",
    restorePointDesc: "Recommended. Creates a restore point so you can roll back if anything goes wrong.",
    undoCenter: "Undo Center",
    undoAll: "Undo All",
    undoBySafety: "Undo by Safety Level",
    profiles: "Profiles",
    saveCurrent: "Save Current",
    compare: "Compare",
    selectLabel: "Select:",
    filterLabel: "Filter:",
    enabled: "Enabled",
    kbAllSafe: "All Safe",
    kbSafeMod: "Safe+Mod",
    kbNone: "None",
  },
  ar: {
    appTitle: "وين بوست إنستول",
    appVersion: "v4.1.7 محسن",
    tabDashboard: "لوحة التحكم",
    tabSoftware: "البرمجيات",
    tabProfiles: "الملفات الشخصية",
    tabUndo: "التراجع",
    tabPreview: "المعاينة",
    quickSelect: "تحديد سريع",
    allSafe: "آمن فقط",
    safePlusModerate: "آمن + متوسط",
    allSettings: "الكل",
    noneSettings: "لا شيء",
    safe: "آمن",
    moderate: "متوسط",
    risky: "محفوف بالمخاطر",
    previewChanges: "معاينة التغييرات",
    confirmApply: "تأكيد وتطبيق",
    noChanges: "لا توجد تغييرات محددة",
    safetyWarnings: "تحذيرات الأمان",
    settingConflicts: "تعارضات الإعدادات",
    createRestorePoint: "إنشاء نقطة استعادة النظام قبل التطبيق",
    restorePointDesc: "موصى به. ينشئ نقطة استعادة حتى تتمكن من التراجع إذا حدث خطأ.",
    undoCenter: "مركز التراجع",
    undoAll: "التراجع عن الكل",
    undoBySafety: "التراجع حسب مستوى الأمان",
    profiles: "الملفات الشخصية",
    saveCurrent: "حفظ الحالي",
    compare: "مقارنة",
    selectLabel: "تحديد:",
    filterLabel: "تصفية:",
    enabled: "مفعّل",
    kbAllSafe: "آمن فقط",
    kbSafeMod: "آمن+متوسط",
    kbNone: "لا شيء",
  },
  zh: {
    appTitle: "WinPostInstall",
    appVersion: "v4.1.7 优化工具",
    tabDashboard: "仪表板",
    tabSoftware: "软件",
    tabProfiles: "配置方案",
    tabUndo: "撤销",
    tabPreview: "预览",
    quickSelect: "快速选择",
    allSafe: "仅安全项",
    safePlusModerate: "安全+中等",
    allSettings: "全部",
    noneSettings: "无",
    safe: "安全",
    moderate: "中等",
    risky: "高风险",
    previewChanges: "预览更改",
    confirmApply: "确认并应用",
    noChanges: "未选择任何更改",
    safetyWarnings: "安全警告",
    settingConflicts: "设置冲突",
    createRestorePoint: "应用前创建系统还原点",
    restorePointDesc: "建议开启。创建还原点以便出现问题时可以回退。",
    undoCenter: "撤销中心",
    undoAll: "全部撤销",
    undoBySafety: "按安全级别撤销",
    profiles: "配置方案",
    saveCurrent: "保存当前",
    compare: "对比",
    selectLabel: "选择:",
    filterLabel: "筛选:",
    enabled: "已启用",
    kbAllSafe: "仅安全",
    kbSafeMod: "安全+中",
    kbNone: "无",
  },
};

interface I18nContextType {
  locale: Locale;
  setLocale: (locale: Locale) => void;
  t: TranslationStrings;
  dir: "ltr" | "rtl";
}

const I18nContext = createContext<I18nContextType>({
  locale: "en",
  setLocale: () => {},
  t: translations.en,
  dir: "ltr",
});

export function useI18n() {
  return useContext(I18nContext);
}

export function I18nProvider({ children }: { children: React.ReactNode }) {
  const [locale, setLocaleState] = useState<Locale>("en");

  useEffect(() => {
    const saved = localStorage.getItem("winpostinstall-locale") as Locale;
    if (saved && translations[saved]) setLocaleState(saved);
  }, []);

  const setLocale = useCallback((l: Locale) => {
    setLocaleState(l);
    localStorage.setItem("winpostinstall-locale", l);
  }, []);

  const t = translations[locale];
  const dir = locale === "ar" ? "rtl" : "ltr";

  return (
    <I18nContext.Provider value={{ locale, setLocale, t, dir }}>
      {children}
    </I18nContext.Provider>
  );
}

export const localeNames: Record<Locale, string> = {
  en: "English",
  ar: "العربية",
  zh: "中文",
};
