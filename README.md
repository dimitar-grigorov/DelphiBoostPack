# DelphiBoostPack

Welcome to DelphiBoostPack, a comprehensive utility library designed to enhance and extend the capabilities of Delphi 2007 and earlier versions. This repository aims to bridge the gap between older Delphi environments and modern software development practices by providing a collection of utilities, classes, and routines that incorporate features commonly found in newer programming languages.

**Intent of the Repository:**

Our goal is to support the Delphi developer community by offering easy-to-integrate solutions that improve productivity, code maintainability, and application performance. Whether you're working with databases, managing collections, or requiring advanced data manipulation, DelphiBoostPack offers a suite of tools to streamline your development process without the need to upgrade from your trusted Delphi version.

**Development and Compatibility:**

The main development of DelphiBoostPack is done on Delphi 2007, ensuring that the tools and utilities are optimized for this version. However, the plan is to support a wide range of Delphi versions, from Delphi 7 to Delphi 11.3. This broad compatibility range is intended to make the utilities accessible and beneficial to developers working across different versions of Delphi, allowing for a modern development experience even on older platforms.

## Coding Style Guidelines

To maintain consistency and code readability within the DelphiBoostPack, we adhere to the following coding style guidelines:

-   **Local Variables**: All local variables must start with the `lv` prefix, e.g., `lvIndex`, `lvName`.
-   **Global Variables**: Global variables should start with the `gv` prefix, e.g., `gvApplicationState`, `gvUserCount`.
-   **Local Constants**: Prefix local constants with `lc`, e.g., `lcMaxSize`, `lcFilePath`.
-   **Global Constants**: Global constants must start with `gc`, e.g., `gcAppName`, `gcVersion`.
-   **Class Prefix**: Most classes within the repository must have the prefix `Tbp` (from Boost Pack), indicating their belonging to the DelphiBoostPack collection, e.g., `TbpCustomList`, `TbpDatabaseConnector`.
-   **Unit Naming**: All unit names must end with the word "Unit" to clearly indicate their content and purpose. It is recommended that one unit contains only one class to maintain clarity and ease of maintenance. For instance, the class `TbpIntegerList` should be located in the unit named `bpIntegerListUnit.pas`.

By following these guidelines, we ensure that the codebase remains organized, intuitive, and accessible to contributors and users alike.

## Contribution.

We welcome contributions from the Delphi community! Whether you're fixing a bug, adding a new utility, or improving documentation, your input is valuable. Please feel free to fork the repository, make your changes, and submit a pull request.
