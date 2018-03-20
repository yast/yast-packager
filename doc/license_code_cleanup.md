1.0 License locations
=======================

1.1 Old licenses stile still be used in TW and 3rd parties:
------------------------------------------------------------
  https://download.opensuse.org/tumbleweed/repo/oss/license.tar.gz
  content:
```
  < no-acceptance-needed
  < license.ar.txt
  < license.ca.txt
  < license.cs.txt
  < license.da.txt
  < license.de.txt
  < license.txt
```
  This license has to be handled by YAST manually (without libzypp).

1.2 libzypp licenses of SLES15, LEAP,...:
------------------------------------------
  https://download.opensuse.org/distribution/leap/15.0/repo/oss/repodata/61add773f5583f065ff25a54eb476023dc2a906cabb1ce0740f5223a70b650dc-license.tar.gz

  The content is the same as in 1.1 described.

  This license will be handled by libzypp completely.


1.3 SCC licenses
-----------------
  The SCC license accesses to the repository that is granted *after* registering, but you
  need to accept the license *before* registering. So for the SCC license there is a separate
  repository which has public access and contains only the license.

  https://updates.suse.com/SUSE/Products/SLE-WE/12-SP3/x86_64/product.license/
  content:

```
  < license.de.txt
  < license.es.txt
  < license.fr.txt
  < license.it.txt
  < license.ja.txt
  < license.ko.txt
  < license.pt_BR.txt
  < license.ru.txt
  < license.txt
```

  Without file "no-acceptance-needed". So it has to be accepted by the user.

2.0 Product description:
==========================

```
lib/y2packager/product.rb
product.rb - Handles all product items.

  Y2Packager::Product.selected_base
  <instance>.license_confirmation_required?
  <instance>.license_confirmed?
  <instance>.license
  <instance>.license?
  <instance>.version
  <instance>.name
  ...
  ..
  .

modules/Product.rb

  Product.FindBaseProducts
  Product.ReadProducts
  <instance>.version
  <instance>.name
  ...
  ..
  .

lib/y2packager/product_reader.rb
  Reads the product information from libzypp 

lib/y2packager/product_sorter.rb
  Sorting Products in required display order

lib/y2packager/release_notes_store.rb
lib/y2packager/release_notes.rb
lib/y2packager/release_notes_content_prefs.rb
lib/y2packager/release_notes_reader.rb
  Handles release notes for a given product
```

3.0 Installation workflow
================================

3.1 Calling client/inst_complex_welcome.rb
-------------------------------------------
  and lib/installation/clients/inst_complex_welcome.rb
```
  - calling ::Installation::Dialogs::ComplexWelcome.run(product)
    (file: lib/installation/dialogs/complex_welcome.rb)   
       - installation: product = Y2Packager::Product.available_base_products
       - upgrade && more available products: product = []
    - checking if there is only ONE product available:
       no:  selecting product
            calling ::Installation::Widgets::ProductSelector
            (file: lib/installation/widgets/product_selector.rb)
       yes: showing and accepting this one license
            calling Y2Packager::Widgets::ProductLicense
            (file: lib/y2packager/widgets/product_license.rb)
              - using Widgets::ProductLicenseContent (license text ONLY)
                (file: lib/y2packager/widgets/product_license_content.rb)
              - using Widgets::ProductLicenseConfirmation (Accept button)
                (file: lib/y2packager/widgets/product_license_confirmation.rb)
                Calling product.license_confirmation to write decision.
              - using LicenseTranslationsButton
                (file: lib/y2packager/widgets/license_translations_button.rb)
                This button calls Y2Packager::Dialogs::ProductLicenseTranslations
                which is a popup. (file: lib/y2packager/dialogs/product_license_translations.rb)
```

3.2 Calling client/inst_product_license.rb
-------------------------------------------
  and lib/y2packager/clients/inst_product_license.rb 
```
  - calling Y2Packager::Dialogs::InstProductLicense(product)
    (file: lib/y2packager/dialogs/inst_product_license.rb)
    - using Widgets::ProductLicenseTranslations (license WITH language selection)
      (file: lib/y2packager/widgets/product_license_translationns.rb)
        - using Y2Packager::Widgets::SimpleLanguageSelection (language selection)
          (file lib/y2packager/widgets/simple_language_translations.rb)
        - using Y2Packager::Widgets::ProductLicenseContent (license text ONLY)
          (file: lib/y2packager/widgets/product_license_content.rb)
    - using Widgets::ProductLicenseConfirmation (Accept button)
      (file: lib/y2packager/widgets/product_license_confirmation.rb)
         Calling product.license_confirmation to write decision.
```
  
4.0 Adding a new product
==========================

Calling ProductLicense.AskAddOnLicenseAgreement(src_id) (file: modules/AddOnProduct.rb):
  - ProductLicense.AskAddOnLicenseAgreement(src_id)

The class ProductLicense (file: modules/ProductLicense.rb) is quite old and handles
the licenses acceptance completely (reading, showing and accepting license)
It can handle all license types ( license is in /license.tar.gz, SCC license and libzypp license )
License types are stored under /tmp/YaST2-<number>/product-license .

5.0 Firstboot module
======================
There are two available clients for checking licenses:

5.1 firstboot_license_novell
-----------------------------
( file: clients/firstboot_license_novell.rb )
This is Novell only and should be obsolete.

5.2 firstboot_licenses
-----------------------
( file: clients/firstboot_licenses.rb )
Checking Novell and SUSE licenses. ( Directories are defined in sysconfig.firstboot )
- Calling clients/inst_license.rb
  and lib/installation/clients/inst_license.rb
  This client uses modules/ProductLicense.rb which is explained in 4.0:
    - ProductLicense.AskInstalledLicensesAgreement
    - ProductLicense.AskFirstStageLicenseAgreement (obsolete by inst_complex_welcome)

6.0 SCC licenses
==================
AddonEulaDialog (file lib/registration/ui/addon_eula_dialog.rb) is used for accepting
special SCC licenses which have to be accepted before the regarding repo will be loaded.
(see 1.3)

This lib uses modules/ProductLicense.rb which is explained in 4.0.

Only the UI part is used in ProductLicense.rb

- Yast::ProductLicense.SetAcceptanceNeeded(id, true) - Product has to be accepted
- Yast::ProductLicense.license_file_print = ... - Setting print path
- Yast::ProductLicense.DisplayLicenseDialogWithTitle(...) - Establish UI
- Yast::ProductLicense.HandleLicenseDialogRet(...) - User acceptance

7.0 Upgrade
=============

Calling clients/inst_product_upgrade_license.rb
and lib/y2packager/clients/inst_repositories_initialization.rb.
This class uses Y2Packager::Dialogs::InstProductLicense(product)
(file: lib/y2packager/dialogs/inst_product_license.rb) which is already described in
section 3.2.

8.0 AutoYaST installation/update
==================================
AY uses the same codestream as the normal installation/updated (described in section 3.2.).

9.0 Cleanup
============

9.1 General
------------
We have two main code streams which handles license agreements. 

9.1.1 New code stream
- - - - - - - - - - - -
```
lib/y2packager/dialogs/inst_product_license.rb
lib/y2packager/dialogs/product_license_translations.rb
lib/y2packager/widgets/product_license.rb
lib/y2packager/widgets/product_license_content.rb
lib/y2packager/widgets/product_license_confirmation.rb
lib/y2packager/widgets/simple_language_translations.rb
lib/y2packager/widgets/license_translations_button.rb
```

Handles libzypp licenses (section 1.2 ) only.

Is used for Installation/Update workflow.

9.1.2 Old code stream
- - - - - - - - - - - -

modules/ProductLicense.rb

Handles all licenses types described in section 1.0.
Sitll used for Add-Ons, SCC licenses, first-boot workflow.

9.2 Cleanup modules
--------------------

9.2.1 Unifiy product classes
- - - - - - - - - - - - - - -
Both of these two classes provide information about products (some information is double):

```
lib/y2packager/product.rb
modules/Product.rb
```

Would it makes sense to put it into one class or to include one class into another at least ?

9.2.2 Abstraction of license locations
- - - - - - - - - - - - - - - - - - - - 
The three kind of licenses (section 1.0) should be abstracted in one class (e.g. product.rb)
and should not be located in different classes/modules/UIs.

9.2.3 Removing old Code Stream 
- - - - - - - - - - - - - - - - -
Replacing modules/ProductLicense.rb by the new code stream. So, following workflows have to
be adapted:
- Adding a new product (section 4.0)
- Firstboot module (section 5.0)
- SCC licenses (section 6.0)

The UI of the old code stream is showing the location of the stored license
text. If this is still needed we would have to add this in the new code stream
too.

This is requested in:

https://trello.com/c/tUy82u79/2112-create-bug-report-add-license-url-to-product-license-dialog
            

9.2.4 Code cleanup in Firstboot module
- - - - - - - - - - - - - - - - - - - - -
Removing all old NOVELL license stuff.

9.3 Additional code changes
-----------------------------

- Make it configurable in the control file where to show the product license if there is
  `just one product` on the media (default behavior "as is" now)
- The rest of the requirements should already be fulfilled or quite simple to implement it.
  After refactoring It has to be checked again.
