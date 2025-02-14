## PowerShell Module for N-Central(c) by N-Able
##
## Version	:	1.3
## Author	:	Adriaan Sluis (as@tosch.nl)
##
## !Still some Work In Progress!
##
## Provides a PowerShell Interface for N-Central(c)
## Uses the SOAP-API of N-Central(c) by N-Able
## Completely written in PowerShell for easy reference/analysis.
##

##Copyright 2022 Tosch Automatisering
##
##Licensed under the Apache License, Version 2.0 (the "License");
##you may not use this file except in compliance with the License.
##You may obtain a copy of the License at
##
##    http://www.apache.org/licenses/LICENSE-2.0
##
##Unless required by applicable law or agreed to in writing, software
##distributed under the License is distributed on an "AS IS" BASIS,
##WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
##See the License for the specific language governing permissions and
##limitations under the License.
##

## Change log
##
## v1.2		Feb 24, 2021
## -Made PowerShell 7 compatible by removing usage of WebServiceProxy.
## -Sorting CustomProperty-columns by default (NoSort/UnSorted Option)
## -JWT-option in New-NCentralConnection
##
## v1.3		TBD
## -CustomProperty 	- Get individual Property Values.
## -CustomProperty 	- Add/Remove individual (Comma-separated) values inside the CP.
## -CustomProperty 	- Optional Base64 Encoding/Decoding.
## -CustomerDetails	- ValidationList for standard-/custom-property filled by API-query.
## -Enhanced Get-NCAccessGroupList/Detail
## -Enhanced Get-NCUserRoleList/Detail
##
## -CP -Backup/Restore to/from JSON 
##

#Region Classes and Generic Functions
using namespace System.Net

Class NCentral_Connection {
## Using the Interface ServerEI2_PortType
## See documentation @:
## http://mothership.n-able.com/dms/javadoc_ei2/com/nable/nobj/ei2/ServerEI2_PortType.html

#Region Properties

	## TODO - Enum-lists for StatusIDs, ErrorIDs, ...
	## TODO - Cleanup WebProxy code (whole module)

	## Initialize the API-specific values (as static).
	## No separate NameSpace needed because of Class-enclosure. Instance NameSpace available as Property.
	#static hidden [String]$NWSNameSpace = "NCentral" + ([guid]::NewGuid()).ToString().Substring(25)
	static hidden [String]$SoapURL = "/dms2/services2/ServerEI2?wsdl"

	
	## Create Properties
	static [String]$PSNCVersion = "1.3"		## The PS-NCentral version
	[String]$ConnectionURL					## Server FQDN
	[String]$BindingURL						## Full SOAP-path
	[String]$AllProtocols = 'tls12,tls13'	## Https encryption
	[Boolean]$IsConnected = $false			## Connection Status
	hidden [PSCredential]$Creds = $null		## Encrypted Credentials

	hidden [Object]$Connection				## Store Server Session
	#hidden [Object]$NameSpace				## For accessing API-Class Objects (WebServiceProxy)
	[int]$RequestTimeOut = 100				## Default timeout in Seconds
	hidden [Object]$ConnectedVersion		## For storing full VersionInfoGet-data
	[String]$NCVersion						## The UI-version of the connected server
	[int]$DefaultCustomerID					## Used when no CustomerID is supplied in most device-commands
	[Object]$Error							## Last known Error

	## Create a general Key/Value Pair. Will be casted at use. Skipped in most methods for non-reuseablity.
	## Integrated (available in session only): $KeyPair = New-Object -TypeName ($NameSpace + '.tKeyPair')
	#hidden $KeyPair = [PSObject]@{Key=''; Value='';}

	## Create Key/Value Pairs container(Array).
	hidden [Array]$KeyPairs = @()

	## Defaults and ValidationLists
	hidden [Array]$rc									#Returned Raw Collection of NCentral-Data.
	hidden [Object]$CustomerData						#Caching of CustomerData for quick reference
	hidden [Boolean]$CustomerDataModified = $false		#Cache rebuild flag
	hidden [Array]$CustomerValidation = @()				#Supports decision between Customer- and Organization-properties. Used to be hardcoded.
	hidden [Collections.ArrayList]$RequestFilter = @()	#Limit/Filter AssetDetail categories

	## Work In Progress
	#$tCreds

	## Testing / Debugging only
	hidden $Testvar
#	$this.Testvar = $this.GetType().name
	

#EndRegion	
	
#Region Constructors

	#Base Constructors
	## Using ConstructorHelper for chaining.
	
	NCentral_Connection(){
	
		Try{
			## [ValidatePattern('^server\d{1,4}$')]
			$ServerFQDN = Read-Host "Enter the fqdn of the N-Central Server"
		}
		Catch{
			Write-Host "Connection Aborted"
			Break
		}
		$PSCreds = Get-Credential -Message "Enter NCentral API-User credentials"
		$this.ConstructorHelper($ServerFQDN,$PSCreds)
	}
	
	NCentral_Connection([String]$ServerFQDN){
		$PSCreds = Get-Credential -Message "Enter NCentral API-User credentials"
		$this.ConstructorHelper($ServerFQDN,$PSCreds)
	}
	
	NCentral_Connection([String]$ServerFQDN,[String]$JWT){
		$SecJWT = (ConvertTo-SecureString $JWT -AsPlainText -Force)
		$PSCreds = New-Object PSCredential ("_JWT", $SecJWT)
		$this.ConstructorHelper($ServerFQDN,$PSCreds)
	}

	NCentral_Connection([String]$ServerFQDN,[PSCredential]$PSCreds){
		$this.ConstructorHelper($ServerFQDN,$PSCreds)
	}

	hidden ConstructorHelper([String]$ServerFQDN,[PSCredential]$Credentials){
		## Constructor Chaining not Standard in PowerShell. Needs a Helper-Method.
		##
		## ToDo: 	ValidatePattern for $ServerFQDN
			
		If (!$ServerFQDN){	
			Write-Host "Invalid ServerFQDN given."
			Break
		}
		If (!$Credentials){	
			Write-Host "No Credentials given."
			Break
		}

		## Construct Session-parameters.
		## Place in Class-Property for later reference.
		$this.ConnectionURL = $ServerFQDN		
		$this.Creds = $Credentials

		#Write-Debug "Connecting to $this.ConnectionURL."
		$this.bindingURL = "https://" + $this.ConnectionURL + [NCentral_Connection]::SoapURL

		## Remove existing/previous default-instance. Clears previous login.
		If($null -ne $Global:_NCSession){
			Remove-Variable _NCSession -scope global
		}

		## Initiate the session to the NCentral-server.
		$this.Connect()
	
	}	
	

#EndRegion

#Region Methods
#	## Features
#	## Returns all data as Object-collections to allow pipelines.
#	## Mimic the names of the API-method where possible.
#	## Supports Synchronous Requests only (for now).
#	## NO 'Dangerous' API's are implemented (Delete/Remove).
#	## 	
#	## To Do
#	## TODO - Check for $this.IsConnected before execution.
#	## TODO - General Error-handling + customized throws.
#	## TODO - Additional Add/Set-methods
#	## TODO - Progress indicator (Write-Progress)
#	## TODO - DeviceAssetInfoExportWithSettings options (Exclude/Include)
#	## TODO - Error on AccessGroupGet
#	## TODO - Async processing
#	##

	#Region ClassSupport

    ## Connection Support
	[void]Connect(){
	
		## Clear existing connection (if any)
		$this.Connection = $null
		$this.IsConnected = $false

		## Secure communications
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
		[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]$this.AllProtocols

<#		Use of WebProxy deprecated. Not PS7 compatible.
		Try{
			## Connect to Soap-service. Use ErrorAction to enable Catching.
			## Explicit Namespace not needed at creation when used inside a Class.
			## Credentials needed for NCentral class-access/queries only. Not checked for setting connection.
			#$this.Connection = New-Webserviceproxy $this.bindingURL -credential $this.creds -Namespace [NCentral_Connection]::NWSNameSpace -ErrorAction Stop
			#$this.Connection = New-Webserviceproxy $this.bindingURL -credential $this.creds -ErrorAction Stop
			$this.Connection = New-Webserviceproxy $this.bindingURL -ErrorAction Stop
		}
		Catch [System.Net.WebException]{
		    #Write-Host ([string]::Format("Error : {0}", $_.Exception.Message))
			$this.Error = $_
			$this.ErrorHandler()
		}

		## Connection Properties/Methods
		#Write-host $this.connection | Get-Member -Force

		## Connecting agent info. Only available after succesful connection with Credentials.
		#Write-Host $this.connection.useragent


		## API-Class Properties/Methods base
		#$this.NameSpace = $this.connection.GetType().namespace
		#Write-host $this.NameSpace| Get-Member -Force

		## Determine NCentral Version		
		## Errors when using New-Webserviceproxy. DataType Error, Not CLS-compliant.
		## Use plain ei2-Envelope and Invoke-RestMethod
#>

## Use versionInfoGet, Includes checking SOAP-connection
## No credentials needed (yet).
$VersionEnvelope = @"
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:ei2="http://ei2.nobj.nable.com/">
   <soap:Header/>
   <soap:Body>
      <ei2:versionInfoGet/>
   </soap:Body>
</soap:Envelope>
"@

		Try{
			$this.ConnectedVersion = (Invoke-RestMethod -Uri $this.BindingURL -body $VersionEnvelope -Method POST -TimeoutSec $this.RequestTimeOut).
			envelope.body.versionInfoGetResponse.return | Select-Object key,value
		}
#		Catch [System.Net.WebException]{
#			$this.Error = $_
#			$this.ErrorHandler()
#		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}
		## Extract NCental UI version from returned data
		$this.NCVersion = ($this.Connectedversion | Where-Object {$_.key -eq "Installation: Deployment Product Version"} ).value


		## TODO Make valid check on connection-error (incl. Try/Catch)
		## Now checking on version-data retrieval.
#		if ($this.Connection){
#		if ($this.Connection.useragent){
		if ($this.NCVersion){
			$this.IsConnected = $true
		}

		## Fill cache-settings

		## Store names of standard customer-properties. For differentiating from COPs.
		$this.CustomerValidation = ($this.customerlist($true) | get-member | where-object {$_.membertype -eq "noteproperty"} ).name


	}

	hidden [String]PlainUser(){
		$CredUser = $this.Creds.GetNetworkCredential().UserName

		If ($CredUser -eq '_JWT'){
			Return $null
		}
		Else{
			Return $CredUser
		}
	}
	
	hidden [String]PlainPass(){
		Return $this.Creds.GetNetworkCredential().Password
	}

	[void]ErrorHandler(){
		$this.ErrorHandler($this.Error)
	}

	[void]ErrorHandler($ErrorObject){
	
		#Write-Host$ErrorObject.Exception|Format-List -Force
		#Write-Host ($ErrorObject.Exception.GetType().FullName)
#		$global:ErrObj = $ErrorObject


#		Write-Host ($ErrorObject.Exception.Message)
		Write-Host ($ErrorObject.ErrorDetails.Message)
		
#		Known Errors List:
#		Connection-error (https): There was an error downloading ..
#	    1012 - Thrown when mandatory settings are not present in "settings".
#	    2001 - Required parameter is null - Thrown when null values are entered as inputs.
#	    2001 - Unsupported version - Thrown when a version not specified above is entered as input.
#	    2001 - Thrown when a bad username-password combination is input, or no PSA integration has been set up.
#	    2100 - Thrown when invalid MSP N-central credentials are input.
#	    2100 - Thrown when MSP-N-central credentials with MFA are used.
#	    3010 - Maximum number of users reached.
#	    3012 - Specified email address is already assigned to another user.
#	    3014 - Creation of a user for the root customer (CustomerID 1) is not permitted.
#	    3014 - When adding a user, must not be an LDAP user.
#		3022 - Customer/Site already exists.
#		3026 - Customer name length has exceeded 120 characters.
#		4000 - SessionID not found or has expired.
#	    5000 - An unexpected exception occurred.
#		5000 - Query failed.
#		5000 - javax.validation.ValidationException: Unable to validate UI session
#    	9910 - Service Organization already exists.
		
		Break
	}

	## API Requests
	hidden [Object]NCWebRequest([String]$APIMethod,[String]$APIData){

		Return $this.NCWebRequest($APIMethod,$APIData,'')
	}

	hidden [Object]NCWebRequest([String]$APIMethod,[String]$APIData,$Version){
	## Basic NCentral SOAP-request, invoking Credentials.

	## Optionally invoke version (specific requests)
	#version - Determines whether MSP N-Central or PSA credentials are to be used. In the case of PSA credentials the number indicates the type of PSA integration setup.
	#	"0.0" indicates that MSP N-central credentials are to be used.
	#	"1.0" indicates that a ConnectWise PSA integration is to be used.
	#	"2.0" indicates that an Autotask PSA integration is to be used.
	#	"3.0" indicates than a Tigerpaw PSA integration is to be used.
	$VersionKey = ''
	If($Version){
		$VersionKey = ("
			<ei2:version>{0}</ei2:version>" -f $Version)
	}

## Build SoapRequest (must be left-lined for structure and ending Here-String --> "@)
$MySoapRequest =(@"
<soap:Envelope xmlns:soap="http://www.w3.org/2003/05/soap-envelope" xmlns:ei2="http://ei2.nobj.nable.com/">
	<soap:Header/>
	<soap:Body>
		<ei2:{0}>{4}
			<ei2:username>{1}</ei2:username>
			<ei2:password>{2}</ei2:password>{3}
		</ei2:{0}>
	</soap:Body>
</soap:Envelope>
"@ -f $APIMethod, $this.PlainUser(), $this.PlainPass(), $APIData, $VersionKey)

		#Write-Host $MySoapRequest			## Debug purpose
		$FullReponse = $null
		Try{
				$FullReponse = Invoke-RestMethod -Uri $this.bindingURL -body $MySoapRequest -Method POST
			}
#		Catch [System.Net.WebException]{
#			    Write-Host ([string]::Format("Error : {0}", $_.Exception.Message))
#				$this.Error = $_
#				$this.ErrorHandler()
#			}
		Catch {
			    Write-Host ([string]::Format("Error : {0}", $_.Exception.Message))
				$this.Error = $_
				$this.ErrorHandler()
			}
							
		#$ReturnProperty = $$APIMethod + "Response"
		$ReturnClass = $FullReponse.envelope.body | Get-Member -MemberType Property
		$ReturnProperty = $ReturnClass[0].Name
				
		Return 	$FullReponse.envelope.body.$ReturnProperty.return
	}

	hidden [Object]GetNCData([String]$APIMethod,[String]$Username,[String]$PassOrJWT,$KeyPairs){
		## Overload for Backward compatibility only
		Return $this.GetNCData($APIMethod,$KeyPairs,'')
	}

	hidden [Object]GetNCData([String]$APIMethod,[Array]$KeyPairs){

		Return $this.GetNCData($APIMethod,$KeyPairs,'')
	}
		
	hidden [Object]GetNCData([String]$APIMethod,[Array]$KeyPairs,[String]$Version){

		## Process Keys to Request-settings
		$MyKeys=""
		ForEach($KeyPair in $KeyPairs){ 
			$MyKeys = $MyKeys + ("
			<ei2:settings>
				<ei2:key>{0}</ei2:key>
				<ei2:value>{1}</ei2:value>
			</ei2:settings>" -f ($KeyPair.Key),($KeyPair.Value))
		}
		## Invoke request
		Return $this.NCWebRequest($APIMethod, $MyKeys,$Version)
	}

	hidden [Object]GetNCDataOP([String]$APIMethod,$CustomerIDs,[Boolean]$ReverseOrder){
		## Get OrganizationProperties for (optional) specified customerIDs
		## Process Array
		$MyKeys=""
		ForEach($CustomerID in $CustomerIDs){ 
			$MyKeys = $MyKeys + ("
			<ei2:customerIds>{0}</ei2:customerIds>" -f $CustomerID)
		}
		## Add mandatory options
		$MyKeys = $MyKeys + ("
			<ei2:reverseOrder>{0}</ei2:reverseOrder>" -f ($ReverseOrder.ToString()).ToLower())

		## Invoke request
		Return $this.NCWebRequest($APIMethod, $MyKeys)
	}

	hidden [Object]GetNCDataDP([String]$APIMethod,$DeviceIDs,$DeviceNames,$FilterIDs,$FilterNames,[Boolean]$ReverseOrder){
		## Get DeviceProperties for (optional) filtered devices
		## Process Arrays
		$MyKeys=""
		ForEach($DeviceID in $DeviceIDs){ 
			$MyKeys = $MyKeys + ("
			<ei2:deviceIDs>{0}</ei2:deviceIDs>" -f $DeviceID)
		}
		ForEach($DeviceName in $DeviceNames){ 
			$MyKeys = $MyKeys + ("
			<ei2:deviceNames>{0}</ei2:deviceNames>" -f $DeviceName)
		}
		ForEach($FilterID in $FilterIDs){ 
			$MyKeys = $MyKeys + ("
			<ei2:filterIDs>{0}</ei2:filterIDs>" -f $FilterID)
		}
		ForEach($FilterName in $FilterNames){ 
			$MyKeys = $MyKeys + ("
			<ei2:filterNames>{0}</ei2:filterNames>" -f $FilterName)
		}
		$MyKeys = $MyKeys + ("
			<ei2:reverseOrder>{0}</ei2:reverseOrder>" -f ($ReverseOrder.ToString()).ToLower())

		## Invoke request
		Return $this.NCWebRequest($APIMethod, $MyKeys)
	}

	hidden [Object]SetNCDataOP([String]$APIMethod,$OrganizationID,$OrganizationPropertyID,[String]$OrganizationPropertyValue){
		## Set a single OrganizationProperty
		## Process Arrays
		$MyKeys=("
			<ei2:organizationProperties>
				<ei2:customerId>{0}</ei2:customerId>
				<ei2:properties>
					<ei2:propertyId>{1}</ei2:propertyId>
					<ei2:value>{2}</ei2:value>
				</ei2:properties>
			</ei2:organizationProperties>" -f $OrganizationID,$OrganizationPropertyID,$OrganizationPropertyValue)

		## Invoke request
		Return $this.NCWebRequest($APIMethod, $MyKeys)
	}

	hidden [Object]SetNCDataDP([String]$APIMethod,$DeviceID,$DevicePropertyID,[String]$DevicePropertyValue){
		## Set a single DeviceProperty
		## Process Arrays
		$MyKeys=("
			<ei2:deviceProperties>
				<ei2:deviceID>{0}</ei2:deviceID>
				<ei2:properties>
					<ei2:devicePropertyID>{1}</ei2:devicePropertyID>
					<ei2:value>{2}</ei2:value>
				</ei2:properties>
			</ei2:deviceProperties>" -f $DeviceID, $DevicePropertyID, $DevicePropertyValue)

		## Invoke request
		Return $this.NCWebRequest($APIMethod, $MyKeys)
	}

    ## Data Management / Processing
	hidden[PSObject]ProcessData1([Array]$InArray){
		## Most Common PairClass is Info or Item.
		## Fill if not specified.

		# Hard (Pre-)Fill
		$PairClass = "info"

		## Base on found Array-Properties if possible
		If($InArray.Count -gt 0){
			$PairClasses = $InArray[0] | Get-member -MemberType Property
			$PairClass = $PairClasses[0].Name
		}
		
		Return $this.ProcessData1($InArray,$PairClass)
	}
	
	hidden[PSObject]ProcessData1([Array]$InArray,[String]$PairClass){
		
		## Received Dataset KeyPairs 2 List/Columns
		$OutObjects = @()
		
		if ($InArray){
			foreach ($InObject in $InArray) {

#				$ThisObject = New-Object PSObject				## In this routine the object is created at start. Properties are added with values.
				$Props = @{}									## In this routine the object is created at the end. Properties from a list.

				## Add a Reference-Column at Object-Level
				If ($PairClass -eq "Properties"){
					## CustomerLink if Available
					if(Get-Member -inputobject $InObject -name "CustomerID"){
#						$ThisObject | Add-Member -MemberType NoteProperty -Name 'CustomerID' -Value $InObject.CustomerID -Force
						$Props.add('CustomerID',$InObject.CustomerID)
					}
					
					## DeviceLink if Available
					if(Get-Member -inputobject $InObject -name "DeviceID"){
#						$ThisObject | Add-Member -MemberType NoteProperty -Name 'DeviceID' -Value $InObject.DeviceID -Force
						$Props.add('DeviceID',$InObject.DeviceID)
					}
				}

				## Convert all (remaining) keypairs to Properties
				foreach ($item in $InObject.$PairClass) {

					## Cleanup the Key and/or Value before usage.
					If ($PairClass -eq "Properties"){
						$Header = $item.label
					}
					Else{
						If($item.key.split(".")[0] -eq 'asset'){	##Should use ProcessData2 (ToDo)
							$Header = $item.key
						}
						Else{
							$Header = $item.key.split(".")[1]
						}
					}

					## Ensure a Flat Value
					If ($item.value -is [Array]){
						$DataValue = $item.Value[0]
					}
					Else{
						$DataValue = $item.Value
					}

					## Now add the Key/Value pairs.
#					$ThisObject | Add-Member -MemberType NoteProperty -Name $Header -Value $DataValue -Force

 					# if a key is found that already exists in the hashtable
			        if ($Props.ContainsKey($Header)) {
			            # either overwrite the value 'Last-One-Wins'
			            # or do nothing 'First-One-Wins'
			            #if ($this.allowOverwrite) { $Props[$Header] = $DataValue }
			        }
			        else {
			            $Props[$Header] = $DataValue
			        }					
#					$Props.add($Header,$DataValue)

				}
				$ThisObject = New-Object -TypeName PSObject -Property $Props	#Alternative option

				## Add the Object to the list
				$OutObjects += $ThisObject
			}
		}
		## Return the list of Objects
		Return $OutObjects
#		$OutObjects
#		Write-Output $OutObjects
	}

	hidden[PSObject]ProcessData2([Array]$InArray){
		## Most Common PairClass is Info or Item.
		## Fill if not specified.
		
		# Hard (Pre-)Fill
		$PairClass = "info"

		## Base on found Array-Properties if possible
		If($InArray.Count -gt 0){
			$PairClasses = $InArray[0] | Get-member -MemberType Property
			$PairClass = $PairClasses[0].Name
		}

		Return $this.ProcessData2($InArray,$PairClass)
	}

	hidden[PSObject]ProcessData2([Array]$InArray,[String]$PairClass){
		
		## Received Dataset KeyPairs 2 Object
		## Key-structure: asset.service.caption.28
		## 
		## Only One Asset at the time can be processed.

		$OutObjects = @()
		$SortedInfo = @()
		$Props = @{}

		$OldArrayID = ""
		[Array]$ArrayProperty = $null
		$OldArrayItemID = ""
		[HashTable]$ArrayItemProperty = @{}
		
		if ($InArray){
			## Get the DeviceId to repeat in every Object-Property
			$CurrentDeviceID = ($InArray.$PairClass | Where-Object {$_.key -eq 'asset.device.deviceid'} | Select-Object value).value
			Write-Debug "DeviceObject CurrentDeviceID: $CurrentDeviceID"
			
			## Sort for processing. Column 2,4
			$SortedInfo = $InArray.$PairClass | Sort-Object @{Expression={$_.key.split(".")[1] + $_.key.split(".")[3]}; Descending=$false}

			$Props = @{}		## In this routine the object is created at the end. Properties from this list.

			## Process the Keypairs
			ForEach ($InObject in $SortedInfo) {

				## Convert the keypairs to Properties
				ForEach ($item in $InObject) {
					
					## Add property direct if column4 does not exist
					## --> Changed to only asset.device items. Header changed accordingly.
					## Build and Add Array if int

#					If(($item.key.split(".")[3]) -lt 0){
					If(($item.key.split(".")[1]) -eq 'device'){
						## Add property as a Non-Array.
						Write-Debug $item.key
#						$Header = ($item.key.split(".")[1])+"."+($item.key.split(".")[2])
						$Header = $item.key.split(".")[2]
						$DataValue = $item.Value

						Write-Debug $Header":"$DataValue

			            $Props[$Header] = $DataValue
						
					}
					Else{
						## Add property as an Array.
						## Make an object-Array Before Adding
						
						## Key-structure: asset.service.caption.28
						## Outer-loop differenting on column 2		MainObject Array-Property
						## Inner-loop differenting on column 4		
						## ObjectItem is column 2.4  (easysplit)	Array-ItemID
						## ObjectHeaders are Column 3				Array-Item-PropertyHeader
						
						
						## Create the Property ItemID from the Key-Name
						$ArrayItemId = ($item.key.split(".")[1])+"."+($item.key.split(".")[3])

						## Is this a new Array-Item?
						If($ArrayItemId -ne $OldArrayItemID){
							## Add the current object to the array-property and start over
							
							If($OldArrayItemID -ne ""){
								Write-Debug "ArrayItemId = $ArrayItemId"
								$ArrayItem = New-Object -TypeName PSObject -Property $ArrayItemProperty
								$ArrayProperty += $ArrayItem
							}							

							$ArrayItemProperty = @{}
							$OldArrayItemID = $ArrayItemId
							
							## Add an unique ID-Column and the DeviceID to the item.
							$ArrayItemProperty["ItemId"]=$ArrayItemId
#							$ArrayItemProperty.add("ItemId", $ArrayItemId)
							$ArrayItemProperty["DeviceId"]=$CurrentDeviceID
						}


						## Create the Main Property Name from the Key-Name
						$ArrayId = ($item.key.split(".")[1])

						## Is this a new Array?
						If($ArrayId -ne $OldArrayID){
							## Add the current array to the main object and start a new one
							
							If($OldArrayID -ne ""){
								Write-Debug "ArrayId = $ArrayId"
				            	$Props[$OldArrayId] = $ArrayProperty
							}

							$ArrayProperty = $null
							$OldArrayID = $ArrayId
						}

						
						## Add the current item to the array-item
						$Header2 = ($item.key.split(".")[2])
						$DataValue2 = $item.Value
						Write-Debug "Header2 = $Header2"
						Write-Debug "DataValue2 = $DataValue2"
						
						$ArrayItemProperty[$Header2]=$DataValue2

					}

				## End of item-loop
				}
				
			## End of Keypairs-loop
			}

			## Debug
#			$this.TestVar = $Props
			
			$ThisObject = New-Object -TypeName PSObject -Property $Props	#Alternative option

			## Add the Object to the list
			$OutObjects += $ThisObject

		## End of Input-check
		}

		## Return the list of Objects
		Return $OutObjects
	}

	[PSObject]IsEncodedBase64([string]$InputString){
		## UniCode by default
		Return $this.IsEncodedBase64($InputString,$false)
	}

	[PSObject]IsEncodedBase64([string]$InputString,[Boolean]$UTF8){

		#[OutputType([Boolean])]
		$DataIsEncoded = $true
	
			Try{
				## Try Decode
				If($UTF8){
					[System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($InputString)) | Out-Null
				}
				Else{
					[System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($InputString)) | Out-Null
				}
			}
			Catch{
				## Data was not encoded yet
				$DataIsEncoded = $false
			}
	
		Return $DataIsEncoded
	}

	[PSObject]ConvertBase64([String]$Data){
		## Encode and Unicode as default
		Return $this.ConvertBase64($Data,$false,$false)
	}

	[PSObject]ConvertBase64([String]$Data,[Bool]$Decode){
		## Unicode as default
		Return $this.ConvertBase64($Data,$Decode,$false)
	}

	[PSObject]ConvertBase64([String]$Data,[Bool]$Decode,[Bool]$UTF8){
	
		## Init
		[string]$ReturnData = $Data
		$DataIsEncrypted = $true			
	
		If($Data){
			## Test content to avoid double-encoding.
			## Still needs some work for false positives. Now checks for valid code-length mainly.
			## Encoded without Byte Order Mark (BOM). Makes recognition difficult.
			Try{
				## Try Decode
				If($UTF8){
					$ReturnData = [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Data))
				}
				Else{
					$ReturnData = [System.Text.Encoding]::Unicode.GetString([System.Convert]::FromBase64String($Data))
				}
			}
			Catch{
				## Data was not valid encoded yet
				$DataIsEncrypted = $false
			}

			## If data should not be decrypted.
			If (!$Decode){
				If ($DataIsEncrypted){
					## Return Already Encrypted Data
					$ReturnData = $Data
				}
				Else{
					## Return Newly Encrypted Data
					If($UTF8){
						$Bytes = [System.Text.Encoding]::UTF8.GetBytes($Data)
					}
					Else {
						$Bytes = [System.Text.Encoding]::Unicode.GetBytes($Data)
					}
					$Returndata = [System.Convert]::ToBase64String($Bytes)
				}
			}
		}

		Return $Returndata
	}
	
    [PSObject]FixProperties([Array]$ObjectArray){
        ## Unifies the properties for all Objects.
        ## Solves Format-Table and Export-Csv issues not showing all properties.

        $ReturnData = $ObjectArray

		Write-host $Returndata

        [System.Collections.ArrayList]$AllColumns=@()
        # Walk through all Objects for Property-names
        $counter = $Returndata.length
        for ($i=0; $i -lt $counter ; $i ++){
            # Get the Property-names
            $Names = ($ReturnData[$i] |Get-Member -type Noteproperty -ErrorAction SilentlyContinue).name

            # Add New or Replace Existing 
            $counter2 = $names.count
            for ($j=0; $j -lt $counter2 ; $j ++){
                $AllColumns += $names[$j]
            }
            # Only unique ColumnNames allowed
            $AllColumns = $AllColumns | Sort-Object -Unique
        }

        Return ($ReturnData | Select-Object $AllColumns)
    }

	#EndRegion
		
	#Region CustomerData
	[Object]ActiveIssuesList([Int]$ParentID){
		# No SearchBy-string adds an empty String.
		return $this.ActiveIssuesList($ParentID,"",0)
	}
	
	[Object]ActiveIssuesList([Int]$ParentID,[String]$IssueSearchBy){
		# No SearchBy-string adds an empty String.
		return $this.ActiveIssuesList($ParentID,$IssueSearchBy,0)
	}

	[Object]ActiveIssuesList([Int]$ParentID,[String]$IssueSearchBy,[Int]$IssueStatus){
		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		## Add parameters as KeyPairs.
		$KeyPair1 = [PSObject]@{Key='customerID'; Value=$ParentID;}
		$this.KeyPairs += $KeyPair1

		## Optional keypair(s) for activeIssuesList. ToDo: Create ENums for choices.

		## SearchBy
		## A string-value to search the: so, site, device, deviceClass, service, transitionTime,
		## notification, features, deviceID, and ip address.
		If ($IssueSearchBy){
			$KeyPair2 = [PSObject]@{Key='searchBy'; Value=$IssueSearchBy;}
			$this.KeyPairs += $KeyPair2
		}
		
		## OrderBy
		## Valid inputs are: customername, devicename, servicename, status, transitiontime,numberofacknoledgednotification,
		## 					serviceorganization, deviceclass, licensemode, and endpointsecurity.
		## Default is customername.
#		$IssueOrderBy = "transitiontime"
#		$KeyPair3 = [PSObject]@{Key='orderBy'; Value=$IssueOrderBy;}
#		$this.KeyPairs += $KeyPair3

		## ReverseOrder
		## Must be true or false. Default is false.
#		$IssueOrderReverse = "true"
#		$KeyPair4 = [PSObject]@{Key='reverseorder'; Value=$IssueOrderReverse;}
#		$this.KeyPairs += $KeyPair4

		## Status
		## Only 1 (last) statusfilter will be applied (if multiple are used in the API).

		$IssueStatusFilter=''
		$IssueAcknowledged = ''

		Switch ($IssueStatus){

			## Valid inputs are: failed, stale, normal, warning, no data, misconfigured, disconnected
			1{
				$IssueStatusFilter='failed'			##
			}
			2{
				$IssueStatusFilter='stale'			##
			}
			3{
				$IssueStatusFilter='normal'			## No returns
			}
			4{
				$IssueStatusFilter='warning'		##
			}
			5{
				$IssueStatusFilter='no data'		##
			}
			6{
				$IssueStatusFilter='misconfigured'	##
			}
			7{
				$IssueStatusFilter='disconnected'	##
			}

			## Valid inputs are: "Acknowledged" or "Unacknowledged"
			11{
				$IssueAcknowledged = "Unacknowledged"
			}
			12{
				$IssueAcknowledged = "Acknowledged"
			}

		}

		## NOC_View_Status_Filter		Reflected in NotifState
		## Valid inputs are: failed, stale, normal, warning, no data, misconfigured, disconnected
		## 'normal' does not return any data.
		If ($IssueStatusFilter){
			$KeyPair5 = [PSObject]@{Key='NOC_View_Status_Filter'; Value=$IssueStatusFilter;}
			$this.KeyPairs += $KeyPair5
		}

		## NOC_View_Notification_Acknowledgement_Filter. Reflected in numberofactivenotification, numberofacknowledgednotification
		## Valid inputs are: "Acknowledged" or "Unacknowledged"
		If ($IssueAcknowledged){
			$KeyPair6 = [PSObject]@{Key='NOC_View_Notification_Acknowledgement_Filter'; Value=$IssueAcknowledged;}
			$this.KeyPairs += $KeyPair6
		}

		$this.rc = $null

		## KeyPairs is mandatory in this query. returns limited list
		Try{
#			$this.rc = $this.Connection.activeIssuesList($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('activeIssuesList', $this.KeyPairs)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}

		## Needs 'issue' iso 'items' for ReturnObjects
#		Return $this.ProcessData1($this.rc, "issue")
		Return $this.ProcessData1($this.rc)
	}

	[Object]JobStatusList([Int]$ParentID){
		## Uses CustomerID. Reports ONLY Scripting-tasks now (not AMP or discovery).

		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		## Add parameters as KeyPairs.
		$KeyPair1 = [PSObject]@{Key='customerID'; Value=$ParentID;}
		$this.KeyPairs += $KeyPair1

		$this.rc = $null

		Try{
#			$this.rc = $this.Connection.jobStatusList($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('jobStatusList', $this.KeyPairs)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}

		Return $this.ProcessData1($this.rc)
	}
	
	[Object]CustomerList(){
	
		Return $this.CustomerList($false)
	}
	
	[Object]CustomerList([Boolean]$SOList){
		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		If($SOList){
			$KeyPair1 = [PSObject]@{Key='listSOs'; Value='true';}
			$this.KeyPairs += $KeyPair1
		}

		$this.rc = $null

		## KeyPairs Array must exist, but is not used in this query.
		Try{
#			$this.rc = $this.Connection.customerList($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('customerList', $this.KeyPairs)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}

#		Return $this.ProcessData1($this.rc, "items")
		Return $this.ProcessData1($this.rc)
	}

	[Object]CustomerListChildren([Int]$ParentID){
		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		## Add parameters as KeyPairs.
		$KeyPair1 = [PSObject]@{Key='customerID'; Value=$ParentID;}
		$this.KeyPairs += $KeyPair1

		$this.rc = $null

		## KeyPairs is mandatory in this query. returns limited list
		Try{
#			$this.rc = $this.Connection.customerListChildren($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('customerListChildren', $this.KeyPairs)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}

#		Return $this.ProcessData1($this.rc, "items")
		Return $this.ProcessData1($this.rc)
	}

	[Object]CustomerPropertyValue([Int]$CustomerID,[String]$PropertyName){

		## Data-caching for faster future-access / lookup.
		If(!$this.CustomerData -Or $this.CustomerDataModified){
			#$this.CustomerData = $this.customerlist() | Select-Object customerid,customername,parentid
			$this.CustomerData = $this.customerlist() | Select-Object customerid,customername,parentid,* -ErrorAction SilentlyContinue
		}

		## Retrieve value from cache
		$Returndata = ($this.CustomerData).where({ $_.customerID -eq $CustomerID }).$PropertyName

		Return $ReturnData

	}

	[Int]CustomerAdd([String]$CustomerName,[Int]$ParentID){
		Return $this.CustomerAdd($CustomerName,$ParentID,@{})
	}

	[Int]CustomerAdd([String]$CustomerName,[Int]$ParentID,$CustomerDetails){

		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		$KeyPair1 = [PSObject]@{Key='customername'; Value=$CustomerName;}
		$this.KeyPairs += $KeyPair1

		$KeyPair2 = [PSObject]@{Key='parentid'; Value=$ParentID;}
		$this.KeyPairs += $KeyPair2

		## Only basic properties are allowed others are skipped. Must be an ordered-/hash-list.
		# Check/build list of Basic properties first
		if (!$this.CustomerValidation){
			$this.CustomerValidation = ($this.customerlist($true) | get-member | where-object {$_.membertype -eq "noteproperty"} ).name
		}

		If($CustomerDetails){
			If ($CustomerDetails -is [System.Collections.IDictionary]){
				ForEach($key in $CustomerDetails.keys){
					If ($this.CustomerValidation -contains $key){
						## This is a standard CustomerProperty.
						#Write-host ("Adding {1} to {0}." -f $key, $CustomerDetails[$key])
						$KeyPair = [PSObject]@{Key=$key; Value=$CustomerDetails[$key];}
						$this.KeyPairs += $KeyPair
					}	
				}
			}Else{
				Write-Host "The customer-details must be given in a Hash or Ordered list."
			}
		}

		$this.rc = $null
		Try{
			## Default GetNCData can be used for API-request
			$this.rc = $this.GetNCData('customerAdd', $this.KeyPairs)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}

		## No dataprocessing needed. Return New customerID
		Return $this.rc[0]
	}

	[void]CustomerModify([Int]$CustomerID,[String]$PropertyName,[String]$PropertyValue){
		## Basic Customer-properties in KeyPairs

		if (!$this.CustomerValidation){
			$this.CustomerValidation = ($this.customerlist($true) | get-member | where-object {$_.membertype -eq "noteproperty"} ).name
		}

		## Validate $PropertyName
		If(!($this.CustomerValidation -contains $PropertyName)){
			Write-Host "Invalid customer field: $PropertyName."
			Break
		}

		#Mandatory (Key) customerid - (Value) the (customer) id of the ID of the existing service organization/customer/site being modified.
		#Mandatory (Key) customername - (Value) Desired name for the new customer or site. Maximum of 120 characters.
		#Mandatory (Key) parentid - (Value) the (customer) id of the parent service organization or parent customer for the new customer/site.
		
		## Lookup Data from cache for mandatory fields related to the $CustomerID.
		$CustomerName = $this.CustomerPropertyValue($CustomerID,"CustomerName")
		$ParentID = $this.CustomerPropertyValue($CustomerID,"ParentID")

		## For an Invalid CustomerID, No additional lookup-data is found.
		If(!$ParentID){
			Write-Host "Unknown CustomerID: $CustomerID."
			Break
		}

		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		## Add Mandatory parameters as KeyPairs.
		$KeyPair1 = [PSObject]@{Key='customerid'; Value=$CustomerID;}
		$this.KeyPairs += $KeyPair1
		
		$KeyPair2 = [PSObject]@{Key="customername"; Value=$CustomerName;}
		$this.KeyPairs += $KeyPair2
		
		$KeyPair3 = [PSObject]@{Key="parentid"; Value=$ParentID;}
		$this.KeyPairs += $KeyPair3

		## PropertyName already validated at CmdLet.
		$KeyPair4 = [PSObject]@{Key=$PropertyName; Value=$PropertyValue;}
		$this.KeyPairs += $KeyPair4

		## Using as [void]: No returndata needed/used.
		Try{
#			$this.Connection.CustomerModify($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			## Standard GetNCData can be used here.
			$this.GetNCData('customerModify', $this.KeyPairs)
        }
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}

		## CustomerData-cache rebuild initiation.
		$this.CustomerDataModified = $true

	}

	[Object]OrganizationPropertyList(){
		# No FilterArray-parameter adds an empty ParentIDs-Array. Returns all customers
		return $this.OrganizationPropertyList(@())
	}
	
	[Object]OrganizationPropertyList([Array]$ParentIDs){
		# Returns all Custom Customer-Properties and values.

		$this.rc = $null
		Try{
#			$this.rc = $this.Connection.organizationPropertyList($this.PlainUser(), $this.PlainPass(), $ParentIDs, $false)
			$this.rc = $this.GetNCDataOP('organizationPropertyList', $ParentIDs, $false)
        }
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}

		Return $this.ProcessData1($this.rc, "properties")
	}

	[Int]OrganizationPropertyID([Int]$OrganizationID,[String]$PropertyName){
		## Search the DevicePropertyID by Name/label (Case InSensitive).
		## Returns 0 (zero) if not found.
		$OrganizationPropertyID = 0
		
		$this.rc = $null
		$OrganizationProperties = $null
		Try{
			## Retrieve a list of the properties for the given OrganizationID
#			$OrganizationProperties = $this.Connection.OrganizationPropertyList($this.PlainUser(), $this.PlainPass(), $OrganizationID, $false)
			$OrganizationProperties = $this.GetNCDataOP('organizationPropertyList', $OrganizationID, $false)
#			$OrganizationProperties = $this.OrganizationPropertyList($OrganizationID)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}
	
		ForEach ($OrganizationProperty in $OrganizationProperties.properties){
			## Case InSensitive compare.
			If($OrganizationProperty.label -eq $PropertyName){
				$OrganizationPropertyID = $OrganizationProperty.PropertyID
			}
		}		
		
		Return $OrganizationPropertyID
	}

	[void]OrganizationPropertyModify([Int]$OrganizationID,[String]$OrganizationPropertyName,[String]$OrganizationPropertyValue){
	
		## Find the propertID by name first.
		[Int]$OrganizationPropertyID = $this.OrganizationPropertyID($OrganizationID,$OrganizationPropertyName)
		If ($OrganizationPropertyID -gt 0){
			[void]$this.OrganizationPropertyModify($OrganizationID,$OrganizationPropertyID,$OrganizationPropertyValue)
		}
		Else{
			## Throw Error
			Write-Host "OrganizationProperty '$OrganizationPropertyName' not found on this Customer."
			Break
		}
	}		
		
	[void]OrganizationPropertyModify([Int]$OrganizationID,[Int]$OrganizationPropertyID,[String]$OrganizationPropertyValue){

		#$OrganizationProperty = [PSObject]@{PropertyID=$OrganizationPropertyID; value=$OrganizationPropertyValue; PropertyIDSpecified='True';}
#		$Organization = [PSObject]@{OrganizationID=$OrganizationID; properties=$OrganizationProperty; OrganizationIDSpecified='True';}
		#$OrganizationPropertyArray = [PSObject]@{CustomerID=$OrganizationID; properties=$OrganizationProperty; CustomerIDSpecified='True';}
		
	
		## Organization-layout:
		# $Organization = [PSObject]@{CustomerID=''; properties=''; CustomerIDSpecified='True';}
		# $Organization = New-Object -TypeName ($this.NameSpace + '.organizationProperties')
		## properties hold an array of DeviceProperties

		## Individual OrganizationProperty layout:
		# $OrganizationProperty = [PSObject]@{PropertyID=''; value=''; PropertyIDSpecified='True';}
		# $OrganizationProperty = New-Object -TypeName ($this.NameSpace + '.organizationProperty')

#        If ($OrganizationPropertyArray){
	        Try{
#				$this.Connection.OrganizationPropertyModify($this.PlainUser(), $this.PlainPass(), $OrganizationPropertyArray)
				$this.SetNCDataOP('organizationPropertyModify',$OrganizationID,$OrganizationPropertyID,$OrganizationPropertyValue)
			}
			Catch {
				$this.Error = $_
				$this.ErrorHandler()
			}
#        }
#        Else{
#			Write-Host "INFO:OrganizationPropertyModify - Nothing to save"
#        }
		
	}
	
	#EndRegion

	#Region DeviceData
	[Object]DeviceList([Int]$ParentID){
		## Use default Settings for DeviceList
		Return $this.Devicelist($ParentID,$true,$false)
	}
	
	[Object]DeviceList([Int]$ParentID,[Bool]$Devices,[Bool]$Probes){
		## Returns only Managed/Imported Items.

		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		## Add parameters as KeyPairs. Need to be unique Objects.
		$KeyPair1 = [PSObject]@{Key='customerID'; Value=$ParentID;}
		$this.KeyPairs += $KeyPair1

		$KeyPair2 = [PSObject]@{Key='devices'; Value=$Devices;}
		$this.KeyPairs += $KeyPair2

		$KeyPair3 = [PSObject]@{Key='probes'; Value=$Probes;}
		$this.KeyPairs += $KeyPair3

		$this.rc = $null
		Try{
#			$this.rc = $this.Connection.deviceList($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('deviceList', $this.KeyPairs)
		}
		Catch{
			$this.Error = $_
			$this.ErrorHandler()
		}
		
#		Return $this.ProcessData1($this.rc, "info")
		Return $this.ProcessData1($this.rc)
	}

	[Object]DeviceGet([int]$DeviceID){
		## Refresh / Clean KeyPair-container.
		
		$this.KeyPairs = @()

		## Add parameter as KeyPair.
		#Write-Host "Adding key for $DeviceID"
		$KeyPair1 = [PSObject]@{Key='deviceID'; Value=$DeviceID;}
		$this.KeyPairs += $KeyPair1

		$this.rc = $null
		Try{
#			$this.rc = $this.Connection.deviceGet($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('deviceGet', $this.KeyPairs)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}
		
		Return $this.ProcessData1($this.rc)
	}

	[Object]DeviceGetAppliance([int]$ApplianceID){
		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		## Add parameter as KeyPair.
		#Write-Host "Adding key for $ApplianceID"
		$KeyPair1 = [PSObject]@{Key='applianceID'; Value=$ApplianceID;}
		$this.KeyPairs += $KeyPair1

		$this.rc = $null
		Try{
#			$this.rc = $this.Connection.deviceGet($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('deviceGet', $this.KeyPairs)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}
		
		Return $this.ProcessData1($this.rc)
	}
		
	[Object]DeviceGetStatus([Int]$DeviceID){
		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		## Add parameters as KeyPairs.
		$KeyPair1 = [PSObject]@{Key='deviceID'; Value=$DeviceID;}
		$this.KeyPairs += $KeyPair1

		$this.rc = $null
	
		Try{
#			$this.rc = $this.Connection.deviceGetStatus($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('deviceGetStatus', $this.KeyPairs)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}
		
#		Return $this.ProcessData1($this.rc, "info")
		Return $this.ProcessData1($this.rc)
	}

	[Object]DevicePropertyList([Array]$DeviceIDs,[Array]$DeviceNames,[Array]$FilterIDs,[Array]$FilterNames){
		## Reports the Custom Device-Properties and values. Uses filter-arrays.
		## Names are Case-sensitive.
		## Returns both Managed and UnManaged Devices.

		$this.rc = $null

		Try{
#			$this.rc = $this.Connection.devicePropertyList($this.PlainUser(), $this.PlainPass(), $DeviceIDs,$DeviceNames,$FilterIDs,$FilterNames,$false)
			$this.rc = $this.GetNCDataDP('devicePropertyList',$DeviceIDs,$DeviceNames,$FilterIDs,$FilterNames,$false)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}

		Return $this.ProcessData1($this.rc, "properties")
	}

	[Int]DevicePropertyID([Int]$DeviceID,[String]$PropertyName){
		## Search the DevicePropertyID with Name-Filter (Case InSensitive).
		## Returns 0 (zero) if not found.
		$DevicePropertyID = 0
		
		$DeviceProperties = $null
		Try{
#			$DeviceProperties = $this.Connection.devicePropertyList($this.PlainUser(), $this.PlainPass(), $DeviceID,$null,$null,$null,$false)
			$DeviceProperties = $this.GetNCDataDP('devicePropertyList',$DeviceID,$null,$null,$null,$false)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}
	
		ForEach ($DeviceProperty in $DeviceProperties.properties){
			## Case InSensitive compare.
			If($DeviceProperty.label -eq $PropertyName){
				$DevicePropertyID = $DeviceProperty.devicePropertyID
			}
		}		
		
		Return $DevicePropertyID
	}

	[void]DevicePropertyModify([Int]$DeviceID,[String]$DevicePropertyName,[String]$DevicePropertyValue){
	
		[Int]$DevicePropertyID = $this.DevicePropertyID($DeviceID,$DevicePropertyName)
		If ($DevicePropertyID -gt 0){
			[void]$this.DevicePropertyModify($DeviceID,$DevicePropertyID,$DevicePropertyValue)
		}
		Else{
			## Throw Error
			Write-Host "DeviceProperty '$DevicePropertyName' not found on this Device."
			Break
#			$this.Error = "DeviceProperty '$DevicePropertyName' not found on this Device."
#			$this.ErrorHandler()
		}

	}

	[void]DevicePropertyModify([Int]$DeviceID,[Int]$DevicePropertyID,[String]$DevicePropertyValue){

		## Create a custom DevicePropertyArray. Details below.
#		$DeviceProperty = [PSObject]@{devicePropertyID=$DevicePropertyID; value=$DevicePropertyValue; devicePropertyIDSpecified='True';}
#		$DevicesPropertyArray = [PSObject]@{deviceID=$DeviceID; properties=$DeviceProperty; deviceIDSpecified='True';}
		
	
		## Device-layout for WebProxy:
		# $Device = [PSObject]@{deviceID=''; properties=''; deviceIDSpecified='True';}
		# $Device = New-Object -TypeName ($this.NameSpace + '.deviceProperties')
		## properties hold an array of DeviceProperties

		## Individual DeviceProperty layout for WebProxy:
		# $DeviceProperty = [PSObject]@{devicePropertyID=''; value=''; devicePropertyIDSpecified='True';}
		# $DeviceProperty = New-Object -TypeName ($this.NameSpace + '.deviceProperty')

#        If ($devicesPropertyArray){
#	        Try{
#                $this.Connection.devicePropertyModify($this.PlainUser(), $this.PlainPass(), $devicesPropertyArray)
				$this.SetNCDataDP('devicePropertyModify',$DeviceID,$DevicePropertyID,$DevicePropertyValue)
#			}
#			Catch {
#				$this.Error = $_
#				$this.ErrorHandler()
#			}
#        }
#        Else{
#			Write-Host "INFO:DevicePropertyModify - Nothing to save"
#        }		
	}

	[Object]DeviceAssetInfoExportDevice(){
		## Reports all details for Monitored Assets.
		## !!! Potentially puts a high load on the NCentral-server!!!
		## Removed/disabled in the Module.
		## Only supporting 'DeviceAssetInfoExportDeviceWithSetting' for a single deviceID.
		
#		## Class: DeviceData
#		##   deviceAssetInfoExport						Deprecated
#		##	 deviceAssetInfoExportDevice				Same as 'WithSettings' without specifying filters.
#		##	 deviceAssetInfoExportDeviceWithSettings
#		##
#		## Reports all Monitored Assets and Details. No filtering by CustomerID or DeviceID. Reports All Assets.
#		## Use without Header-formatting (has sub-headers). Device.customerid=siteid.
#		## Generating this list takes quite a long time. Might even time-out.
#		#$rc = $nws.deviceAssetInfoExport2("0.0", $username, $password)		#Error - nonexisting
#		#$ri = $nws.deviceAssetInfoExport("0.0", $username, $password)		#Error - unsupported version
#		#$ri = $nws.deviceAssetInfoExportDevice("0.0", $username, $password)
#		#$PairClass="info"

		$this.rc = $null
	
		Try{
#			$this.rc = $this.Connection.deviceAssetInfoExportDevice("0.0", $this.PlainUser(), $this.PlainPass())
#			$this.rc = $this.GetNCData('deviceAssetInfoExportDevice','',"0.0")
			
        }
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}
		
		Return $this.rc
#		Return $this.ProcessData1($this.rc, "info")
	}

	[Object]DeviceAssetInfoExportDeviceWithSettings($DeviceIDs){
		## Reports Monitored Assets.
		## Calls Full Command with Parameters
		Return $this.DeviceAssetInfoExportDeviceWithSettings($DeviceIds,$null,$null,$null,$null,$null)
	}

	[Object]DeviceAssetInfoExportDeviceWithSettings($DeviceIDs,[Array]$DeviceNames,[Array]$FilterIDs,[Array]$FilterNames,[Array]$Inclusions,[Array]$Exclusions){
		## Reports Monitored Assets.
		## Currently returns all categories for the selected devices. TODO: category-filtering. 

#		From Documentation:
#		http://mothership.n-able.com/dms/javadoc_ei2/com/nable/nobj/ei2/ServerEI2_PortType.html
#
#		Use only ONE of the following options to limit information to certain devices 	 
#		"TargetByDeviceID" - value for this key is an array of deviceids 	 
#		"TargetByDeviceName" - value for this key is an array of devicenames 	 
#		"TargetByFilterID" - value for this key is an array of filterids 	 
#		"TargetByFilterName" - value for this key is an array filternames 	 

		$this.KeyPairs = @()

		$KeyPair1 = $null
		## Add only one of the parameters as KeyPair. by priority.
		If ($DeviceIDs){
			$KeyPair1 = [PSObject]@{Key='TargetByDeviceID'; Value=$DeviceIDs;}
#			ForEach($DeviceID in $DeviceIDs){
#				$KeyPair1 = [PSObject]@{Key='TargetByDeviceID'; Value=$DeviceID;}
#				$this.KeyPairs += $KeyPair1
#			}

		}ElseIf($FilterIDs){
			$KeyPair1 = [PSObject]@{Key='TargetByFilterID'; Value=$FilterIDs;}
		}ElseIF($DeviceNames){
			$KeyPair1 = [PSObject]@{Key='TargetByDeviceName'; Value=$DeviceNames;}
		}ElseIf($FilterNames){
			$KeyPair1 = [PSObject]@{Key='TargetByFilterName'; Value=$FilterNames;}
		}

		## Do not continue if no filter is specified.
		## Due to potential heavy server load.
		If (!$KeyPair1){
			## TODO: Throw Error
			Break
		}
		$this.KeyPairs += $KeyPair1

#		## Without Inclusion/Exclusion ALL categories will be returned.
#		## Documentation On Inclusion/Exclusion:
#		## Key = "InformationCategoriesInclusion" and Value = String[] {"asset.device", "asset.os"} then only information for these two categories will be returned. 	 
#		## Key = "InformationCategoriesExclusion" and Value = String[] {"asset.device", "asset.os"}
#		## Work in Progress
#
#		## Use an ArrayList to allow addition or removal. Using [void] to suppress response (same as | $null at the end).
#		[System.collections.ArrayList]$RequestFilter = @()
#		[void]$RequestFilter.add("asset.application")
#		[void]$RequestFilter.add("asset.device")					# Always included (Root-item)
#		[void]$RequestFilter.add("asset.device.ncentralassettag")
#		[void]$RequestFilter.add("asset.logicaldevice")
#		[void]$RequestFilter.add("asset.mappeddrive")
#		[void]$RequestFilter.add("asset.mediaaccessdevice")
#		[void]$RequestFilter.add("asset.memory")
#		[void]$RequestFilter.add("asset.networkadapter")
#		[void]$RequestFilter.add("asset.os")
#		[void]$RequestFilter.add("asset.osfeatures")
#		[void]$RequestFilter.add("asset.patch")
#		[void]$RequestFilter.add("asset.physicaldrive")
#		[void]$RequestFilter.add("asset.port")
#		[void]$RequestFilter.add("asset.printer")
#		[void]$RequestFilter.add("asset.raidcontroller")
#		[void]$RequestFilter.add("asset.service")
#		[void]$RequestFilter.add("asset.socustomer")
#		[void]$RequestFilter.add("asset.usbdevice")
#		[void]$RequestFilter.add("asset.videocontroller")
#

		## [ToDo] Category-filtering is not working as documented
		$KeyPair2 = $null

		## inclusion prevails
		If ($Inclusions){
			$this.RequestFilter.clear()
			ForEach($inclusion in $Inclusions){
				## Allow for categorynames without prefix.
				If(($inclusion.split("."))[0] -like "asset"){
					[void]$this.RequestFilter.add($inclusion)
				}
				Else{
					[void]$this.RequestFilter.add("asset.{0}" -f $inclusion)
				}
			}
			$KeyPair2 = [PSObject]@{Key="InformationCategoriesInclusion"; Value=$this.RequestFilter;}
		}
		ElseIf ($Exclusions) {
			$this.RequestFilter.clear()
			ForEach($exclusion in $Exclusions){
				## Allow for categorynames without prefix.
				If(($exclusion.split("."))[0] -like "asset"){
					[void]$this.RequestFilter.add($exclusion)
				}
				Else{
					[void]$this.RequestFilter.add("asset.{0}" -f $exclusion)
				}
			}
			$KeyPair2 = [PSObject]@{Key="InformationCategoriesExclusion"; Value=$this.RequestFilter;}
		}

		If ($KeyPair2){
			$this.KeyPairs += $KeyPair2
		}


		$this.rc = $null
		
		Try{
#			$this.rc = $this.Connection.deviceAssetInfoExportDeviceWithSettings("0.0", $this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			#$this.rc = $this.Connection.deviceAssetInfoExport2("0.0", $this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('deviceAssetInfoExportDeviceWithSettings',$this.KeyPairs,"0.0")

		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}
		
		## Todo: Parameter for what to return:
		##		Flat Object (ProcessData1) or 
		##		Multi-Dimesional Object (ProcessData2).
#		Return $this.ProcessData2($this.rc, "info")
		Return $this.ProcessData2($this.rc)
	}

	#EndRegion

	#Region NCentralAppData
		
#	## To Do
#	## TODO - User/Role/AccessGroup as user-object.
#	## TODO - Filter/Rule list (Not available through API yet)
	
	[Object]AccessGroupList([Int]$ParentID){
		## List All Access Groups
		## Mandatory valid CustomerID (SO/Customer/Site-level), does not seem to use it. 

		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		## Add parameters as KeyPairs.
		$KeyPair1 = [PSObject]@{Key='customerID'; Value=$ParentID;}
		$this.KeyPairs += $KeyPair1

		$this.rc = $null

		Try{
#			$this.rc = $this.Connection.accessGroupList($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('accessGroupList', $this.KeyPairs)
		}
		Catch {
			#$this.ErrorHandler($_)
			$this.Error = $_
			$this.ErrorHandler()
		}
		Return $this.ProcessData1($this.rc)
		#Return $this.ProcessData1($this.rc.where{$_.customerid -eq $parentID})

	}

	[Object]AccessGroupGet([Int]$GroupID){
		## Defaults to CustomerGroup
		Return $this.AccessGroupGet($GroupID,$null,$true)
	}

	[Object]AccessGroupGet([Int]$GroupID,[Boolean]$IsCustomerGroup){
		Return $this.AccessGroupGet($GroupID,$null,$IsCustomerGroup)
	}

	[Object]AccessGroupGet([Int]$GroupID,[Int]$ParentID,[Boolean]$IsCustomerGroup){
		## List Access Groups details.
		## Uses groupID and customerGroup. Gets details for the specified AccessGroup.
		## Mandatory parameters:
		## 		-GroupID		Error: '1012 Mandatory settings not present'
		##		-CustomerGroup	Error: '4100 Invalid parameters'
		##						Must be in Sync with GroupType
		## The ParentID/customerID seems unused.

		If ($null -eq $IsCustomerGroup){
			$IsCustomerGroup = $true
		}

		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		## Add parameters as KeyPairs.
		$KeyPair1 = [PSObject]@{Key='groupID'; Value=$GroupID;}
		$this.KeyPairs += $KeyPair1

		if($ParentID){
			$KeyPair2 = [PSObject]@{Key='customerID'; Value=$ParentID;}
			$this.KeyPairs += $KeyPair2
		}

		$KeyPair3 = [PSObject]@{Key='customerGroup'; Value=$IsCustomerGroup;}
		$this.KeyPairs += $KeyPair3

		$this.rc = $null

		Try{
#			$this.rc = $this.Connection.accessGroupGet($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('accessGroupGet', $this.KeyPairs)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}
	
		Return $this.ProcessData1($this.rc)
	}

	[Object]UserRoleList([Int]$ParentID){
		## List All User Roles
		## Mandatory valid CustomerID (SO/Customer/Site-level), does not seem to use it. 

		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		## Add parameters as KeyPairs.
		$KeyPair1 = [PSObject]@{Key='customerID'; Value=$ParentID;}
		$this.KeyPairs += $KeyPair1

		$this.rc = $null
		Try{
#			$this.rc = $this.Connection.userRoleList($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('userRoleList', $this.KeyPairs)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}

		Return $this.ProcessData1($this.rc)

	}

	[Object]UserRoleGet([Int]$UserRoleID){
		Return $this.UserRoleGet($UserRoleID,$null)
	}

	[Object]UserRoleGet([Int]$UserRoleID,[Int]$ParentID){
		## List User Role details.

		## Refresh / Clean KeyPair-container.
		$this.KeyPairs = @()

		## Add parameters as KeyPairs.
		$KeyPair1 = [PSObject]@{Key='userRoleID'; Value=$UserRoleID;}
		$this.KeyPairs += $KeyPair1

		If($ParentID){
			$KeyPair2 = [PSObject]@{Key='customerID'; Value=$ParentID;}
			$this.KeyPairs += $KeyPair2
		}
		
		$this.rc = $null

		Try{
#			$this.rc = $this.Connection.userRoleGet($this.PlainUser(), $this.PlainPass(), $this.KeyPairs)
			$this.rc = $this.GetNCData('userRoleGet', $this.KeyPairs)
		}
		Catch {
			$this.Error = $_
			$this.ErrorHandler()
		}
		
		Return $this.ProcessData1($this.rc)
	}

	#EndRegion

#EndRegion
}
## Class-section Ends here


#Region Generic Functions

Function Convert-Base64 {
	<#
	.Synopsis
	Encode or Decode a string to or from Base64.
	
	.Description
	Encode or Decode a string to or from Base64.
	Use Unicode (UTF16) by default, UTF8 is optional.
	Protected against double-encoding.
	
	#>

	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,		## to create more descriptive error-message.
               Position = 0,
               HelpMessage = 'Data to process')]
			[String]$Data,

		[Parameter(Mandatory=$false,
               HelpMessage = 'Decode')]
			[switch]$Decode,
	
		[Parameter(Mandatory=$false,
				HelpMessage = 'Use UTF8')]
				[Alias("NoUnicode")]
			[switch]$UTF8
		)

	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
		If (!$Data){
			Write-Host ("No data specfied for {0}." -f $MyInvocation.MyCommand.Name)
			Break
		}
	}
	Process{
	}
	End{
		Return [String]$NCsession.convertbase64($Data,$Decode,$UTF8)
	}
}

Function Format-Properties {
	<#
	.Synopsis
	Unifies the properties for all Objects in a list.
	
	.Description
	Unifies the properties for all Objects in a list.
	Solves Get-Member, Format-Table and Export-Csv 
	issue for not showing all properties.
	
	#>

	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,		## to create more descriptive error-message.
               #ValueFromPipeline = $true,
               Position = 0,
               HelpMessage = 'Array Containing PS-Objects')]
			[Array]$ObjectArray
		)

	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
		If (!$ObjectArray){
			Write-Host ("No data specfied for {0}." -f $MyInvocation.MyCommand.Name)
			Break
		}
	}
	Process{
	}
	End{
		Write-Output $NCsession.FixProperties($ObjectArray)
	}

<#
	## ToDo: Params including Pipeline, Inputcheck, Use FixProperties from Class.
	$ReturnData = $ObjectArray

	[System.Collections.ArrayList]$AllColumns=@()
	# Walk through all Objects
	$counter = $Returndata.length
	for ($i=0; $i -lt $counter ; $i ++){
		# Get the Property-names
		$Names = ($ReturnData[$i] |Get-Member -type Noteproperty -ErrorAction SilentlyContinue).name

		# Add New or Replace Existing 
		$counter2 = $names.count
		for ($j=0; $j -lt $counter2 ; $j ++){
			$AllColumns += $names[$j]
		}
		# Only unique ColumnNames allowed
		$AllColumns = $AllColumns | Sort-Object -Unique
	}

	Return ($ReturnData | Select-Object $AllColumns)
#>

}

#EndRegion

#EndRegion - Classes and Generic Functions

#Region PowerShell CmdLets
#	## To Do
#	## TODO - Error-handling at CmdLet Level.
#	## TODO - Add Examples to in-line documentation.
#	## TODO - Additional CmdLets (DataExport, PSA, CustomerObject, ...) 
#	## 

#Region Module-support
Function New-NCentralConnection{
<#
.Synopsis
Connect to the NCentral server.

.Description
Connect to the NCentral server.
Https is always used, since the data itself is unencrypted.

The returned connection-object allows to extract and manipulate 
NCentral Data through methods of the NCentral_Connection Class.

To show available Commands, type:
Get-NCHelp

.Parameter ServerFQDN
Specify the Server DNS-name for this Connection.
The server needs to have a valid certficate for HTTPS.

.Parameter PSCredential
PowerShell-Credential object containing Username and
Password for N-Central access. No MFA.

.Parameter JWT
String Containing the JavaWebToken for N-Central access.

.Parameter DefaultCustomerID
Sets the default CustomerID for this instance.
The CustomerID can be found in the customerlist.
	CustomerID  1	Root / System
	CustomerID 50 	First ServiceOrganization	(Default)

.Example
$PSUserCredential = Get-Credential -Message "Enter NCentral API-User credentials"
New-NCentralConnection NCserver.domain.com $PSUserCredential


.Example
New-NCentralConnection -ServerFQDN <Server> -JWT <Java Web Token>

Use the line above inside a script for a fully-automated connection.

#>

	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false)][String]$ServerFQDN,
        [Parameter(Mandatory=$false)][PSCredential]$PSCredential,
		[Parameter(Mandatory=$false)][String]$JWT,
        [Parameter(Mandatory=$false)][Int]$DefaultCustomerID = 50
    )
	Begin{
		## Check parameters

		## Clear the ServerFQDN if there is no . in it. Will create dialog.
		If ($ServerFQDN -notmatch "\.") {
			$ServerFQDN = $null
		}

	}
	Process{
		## Store the session in a global variable as the default connection.

		# Initiate the connection with the given information.
		# Prompts for additional information if needed.
		If ($ServerFQDN){
			If ($PSCredential){
				#Write-Host "Using Credentials"
				$Global:_NCSession = [NCentral_Connection]::New($ServerFQDN, $PSCredential)
			}
			Elseif($JWT){
				#Write-Host "Using JWT"
				$Global:_NCSession = [NCentral_Connection]::New($ServerFQDN, $JWT)
			}
			Else {
				$Global:_NCSession = [NCentral_Connection]::New($ServerFQDN)
			}
		}
		Else {
			$Global:_NCSession = [NCentral_Connection]::New()
		}

		## ToDo: Check for succesful connection.
		#Write-Host ("Connection to {0} is {1}." -f $Global:_NCSession.ConnectionURL,$Global:_NCSession.IsConnected)

		# Set the default CustomerID for this session.
		$Global:_NCSession.DefaultCustomerID = $DefaultCustomerID
	}
	End{
		## Return the initiated Class
		Write-Output $Global:_NCSession
	}
}

Function NcConnected{
	<#
	.Synopsis
	Checks or initiates the NCentral connection.
	
	.Description
	Checks or initiates the NCentral connection.
	Returns $true if a connection established.
	
	#>
		
	$NcConnected = $false
	
	If (!$Global:_NCSession){
#		Write-Host "No connection to NCentral Server found.`r`nUsing 'New-NCentralConnection' to connect."
		New-NCentralConnection
	}

	## Succesful connection?	
	If ($Global:_NCSession){
		$NcConnected = $true
	}
	Else{
		Write-Host "No valid connection to NCentral Server."
	}
	
	Return $NcConnected
}
	
Function Get-NCHelp{
<#
.Synopsis
Shows a list of available PS-NCentral commands and the synopsis.

.Description
Shows a list of available PS-NCentral commands and the synopsis.

#>
	Get-Command -Module PS-NCentral | 
	#Where-Object {"IsEncodedBase64" -notmatch $_.name} | 
	Select-Object Name |
	Get-Help | 
	Select-Object Name,Synopsis
}

Function Get-NCVersion{
	<#
	.Synopsis
	Returns the N-Central Version(s) of the connected server.
	
	.Description
	Returns the N-Central Version(s) of the connected server.
	
	#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
				HelpMessage = 'Show API version info')]
				[Alias('FullVersionList','Full')]
		[Switch]$APIVersion,
		
		[Parameter(Mandatory=$false,
				HelpMessage = 'Show GUI version only')]
				[Alias('VersionOnly')]
		[Switch]$Plain,
		
		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}
	Process{
	}
	End{
		## API-version info
		If ($APIVersion){
			Write-Output $NcSession.ConnectedVersion | Format-table
		}

		## Connection info
		If ($Plain){
			Write-Output $NcSession.NCVersion
		}
		Else{
			Write-Output $NcSession
		}

	}
}

Function Get-NCTimeOut{
<#
.Synopsis
Returns the max. time in seconds to wait for data returning from a (Synchronous) NCentral API-request.

.Description
Shows the maximum time to wait for synchronous data-request. Dialog in seconds.

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
				HelpMessage = 'Existing NCentral_Connection')]
		$NcSession
    )
	Begin{
			If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}
	Process{
#		Write-Output ($NCSession.Connection.TimeOut/1000)
		Write-Output ($NCSession.RequestTimeOut)
	}
	End{}
}

Function Set-NCTimeOut{
<#
.Synopsis
Sets the max. time in seconds to wait for data returning from a (Synchronous) NCentral API-request.

.Description
Sets the maximum time to wait for synchronous data-request. Time in seconds.
Range: 15-600. Default is 100.

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
				HelpMessage = 'TimeOut for NCentral Requests in Seconds')]
		[Int]$TimeOut,

		[Parameter(Mandatory=$false,
				HelpMessage = 'Existing NCentral_Connection')]
		$NcSession
    )
	Begin{
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}

		## Limit Range. Set to Default (100000) if too small or no value is given.
#		$TimeOut = $TimeOut * 1000
		If ($TimeOut -lt 15){
			Write-Host "Minimum TimeOut is 15 Seconds. Is now reset to default; 100 seconds"
			$TimeOut = 100
		}
		If ($TimeOut -gt 600){
			Write-Host "Maximum TimeOut is 600 Seconds. Is now reset to Max; 600 seconds"
			$TimeOut = 600
		}
	}
	Process{
#		$NCSession.Connection.TimeOut = ($TimeOut * 1000)
		$NCSession.RequestTimeOut = $TimeOut
#		Write-Output ($NCSession.Connection.TimeOut)
		Write-Output ($NCSession.RequestTimeOut)
	}
	End{}
}
#EndRegion

#Region Customers
Function Get-NCServiceOrganizationList{
<#
.Synopsis
Returns a list of all ServiceOrganizations and their data.

.Description
Returns a list of all ServiceOrganizations and their data.

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
				HelpMessage = 'Existing NCentral_Connection')]
		$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}	
	Process{

	}
	End{
		Write-Output $NcSession.CustomerList($true)
	}
}

Function Get-NCCustomerList{
<#
.Synopsis
Returns a list of all customers and their data. ChildrenOnly when CustomerID is specified.

.Description
Returns a list of all customers and their data.
ChildrenOnly when CustomerID is specified.


## TODO - Integrate Custom-properties
#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
#               ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 0,
               HelpMessage = 'Existing Customer ID')]
		## Default-value is essential for output-selection.
		$CustomerID = 0,
		
		[Parameter(Mandatory=$false,
				HelpMessage = 'Existing NCentral_Connection')]
		$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}	
	Process{
		Write-Debug "CustomerID: $CustomerID"
		If ($CustomerID -eq 0){
			## Return all Customers
#			Write-Output $NcSession.CustomerList()
			$ReturnData = $NcSession.CustomerList()
		}
		Else{
			## Return direct children only.
#			Write-Output $NcSession.CustomerListChildren($CustomerID)
			$ReturnData =  $NcSession.CustomerListChildren($CustomerID)
		}
	}
	End{
		## Alphabetical Columnnames
		$ReturnData | Select-Object ($ReturnData|Get-Member -type Noteproperty -ErrorAction SilentlyContinue).name -ErrorAction SilentlyContinue |
		## Put important fields in front.
		Select-Object customerid,customername,externalid,externalid2,* -ErrorAction SilentlyContinue |
		Write-Output
	}
}

Function Set-NCCustomerDefault{
	<#
	.Synopsis
	Sets the DefaultCustomerID to be used.
	
	.Description
	Sets the DefaultCustomerID to be used, when not supplied as parameter.
	Standard-value: 50 (First Service Organization created).
		
	#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 0,
				HelpMessage = 'Existing Customer ID')]
		$CustomerID,
		
		[Parameter(Mandatory=$false,
				HelpMessage = 'Existing NCentral_Connection')]
		$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
		If(!$CustomerID){
			$CustomerID = 50
		}
	}	
	Process{
		$NcSession.DefaultCustomerID = $CustomerID
		Write-Host ("Default CustomerID now set to: {0}" -f $CustomerID)
	}
	End{
	}
}

Function Get-NCCustomerPropertyList{
<#
.Synopsis
Returns a list of all Custom-Properties for the selected CustomerID(s).

.Description
Returns a list of all Custom-Properties for the selected customers.
If no customerIDs are supplied, data for all customers will be returned.

## TODO - Integrate this in the default NCCustomerList.
#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
#               ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 0,
               HelpMessage = 'Array of Existing Customer IDs')]
			[Alias("CustomerID")]
		[Array]$CustomerIDs,
		
		[Parameter(Mandatory=$false,
			HelpMessage = 'No Sorting of the output')]
			[Alias('UnSorted')]
		[Switch]$NoSort,

		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
	
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	
	}
	Process{
		If ($CustomerIDs){
#			Write-Output $NcSession.OrganizationPropertyList($CustomerIDs)
			$ReturnData = $NcSession.OrganizationPropertyList($CustomerIDs)
		}
		Else{
#			Write-Output $NcSession.OrganizationPropertyList()
			$ReturnData = $NcSession.OrganizationPropertyList()
		}
	}
	End{
		If($NoSort){
			$ReturnData | Write-Output
		}
		Else{
			## Alphabetical Columnnames
			$ReturnData | Select-Object ($ReturnData|Get-Member -type Noteproperty -ErrorAction SilentlyContinue).name -ErrorAction SilentlyContinue |
			## Make CustomerID the first column.
			Select-Object customerid,* -ErrorAction SilentlyContinue |
			Write-Output
		}
	}
}

Function Set-NCCustomerProperty{
<#
.Synopsis
Fills the specified property(name) for the given CustomerID(s). Base64 optional.

.Description
Fills the specified property(name) for the given CustomerID(s).
This can be a default or custom property.
CustomerID(s) must be supplied.
Properties are cleared if no Value is supplied.
Optional Base64 encoding (UniCode/UTF16).

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 0,
               HelpMessage = 'Array of Existing Customer IDs')]
			[Alias("CustomerID")]
		[Array]$CustomerIDs,

		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 1,
               HelpMessage = 'Name of the Customer Custom-Property')]
			[Alias("PropertyName")]
		[String]$PropertyLabel,

		[Parameter(Mandatory=$false,
#               ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 2,
               HelpMessage = 'Value for the Customer Property')]
		[String]$PropertyValue = '',

		[Parameter(Mandatory=$false,
			HelpMessage = 'Encode the PropertyValue')]
			[Alias("Encode")]
		[Switch]$Base64,
			
		[Parameter(Mandatory=$false,		## Optional with $Base64
			HelpMessage = 'Use UTF8 Encoding iso UniCode')]
		[Switch]$UTF8,
			
		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		$CustomerProperty = $false
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
#		If (!$PropertyValue){
#			Write-Host "CustomerProperty '$PropertyLabel' will be cleared."
#		}
		If ($NcSession.CustomerValidation -contains $PropertyLabel){
			## This is a standard CustomerProperty.
			$CustomerProperty = $true
		}
	}
	Process{
		## Encode Data if requested
		If ($Base64){
			$PropertyValue = $NCSession.ConvertBase64($PropertyValue,$false,$UTF8)
		}

		ForEach($CustomerID in $CustomerIDs ){
			## Differentiate between Standard(Customer) and Custom(Organization) properties.
			If ($CustomerProperty){
				$NcSession.CustomerModify($CustomerID, $PropertyLabel, $PropertyValue)
			}
			Else{
				$NcSession.OrganizationPropertyModify($CustomerID, $PropertyLabel, $PropertyValue)
			}
		}
	}
	End{
	}
}

Function Get-NCCustomerProperty{
	<#
	.Synopsis
	Retrieve the Value of the specified property(name) for the Customer(ID). Base64 optional.
	
	.Description
	Retrieve the Value of the specified property(name) for the Customer(ID).
	This can be a default or custom property.
	CustomerID and Propertyname must be supplied.
	(Save) Base64 decoding optional.
	
	#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 0,
				HelpMessage = 'Existing Customer ID')]
			[Alias("ID")]
		[int]$CustomerID,

		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 1,
				HelpMessage = 'Name of the Customer Custom-Property')]
			[Alias("PropertyName")]
		[String]$PropertyLabel,
			
		[Parameter(Mandatory=$false,
			HelpMessage = 'Decode the PropertyValue if needed')]
			[Alias("Decode")]
		[Switch]$Base64,

		[Parameter(Mandatory=$false,		## Optional with $Base64
			HelpMessage = 'Use UTF8 Encoding iso UniCode')]
		[Switch]$UTF8,
			
		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		$CustomerProperty = $false
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
		If ($NcSession.CustomerValidation -contains $PropertyLabel){
			## This is a standard CustomerProperty.
			$CustomerProperty = $true
		}
	}
	Process{
		## Differentiate between Standard(Customer) and Custom(Organization) properties.
		If ($CustomerProperty){
			#$this.CustomerPropertyValue($CustomerID,"CustomerName")
			$ReturnData = $NcSession.CustomerPropertyValue($CustomerID,$PropertyLabel)
		}
		Else{
			$ReturnData = ($NcSession.OrganizationPropertyList($CustomerID)).$PropertyLabel
		}

		## Decode if requested
		If ($Base64){
			If($Returndata){
				$Returndata = $NCSession.ConvertBase64($ReturnData,$true,$UTF8)
			}
		}
	}
	End{
		$Returndata |
		Write-Output
	}
}

Function Add-NCCustomerPropertyValue{
	<#
	.Synopsis
	The Value is added to the comma-separated string of unique values in the Customer Property.
	
	.Description
	The Value is added to the comma-separated string of unique values in the Customer Property.
	Case-sensivity is optional.

	
	#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 0,
				HelpMessage = 'Existing Customer ID')]
		[int]$CustomerID,
			
		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 1,
				HelpMessage = 'Existing Property (name)')]
			[Alias("PropertyLabel","Property","CustomProperty")]
		[string]$PropertyName,

		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 2,
				HelpMessage = 'Value to Add to the String')]
			[Alias("Value")]
		[string]$ValueToInsert,

		[Parameter(Mandatory=$false,
			HelpMessage = 'Preserve Case')]
			[Alias('UseCase')]
		[Switch]$CaseSensitive,

		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}
	Process{
		## Remove Existing
		If ($CaseSensitive){
			[system.collections.arraylist]$ValueList = (Remove-NCCustomerPropertyValue $CustomerID $PropertyName $ValueToInsert -UseCase) -split ","
		}
		Else{
			[system.collections.arraylist]$ValueList = (Remove-NCCustomerPropertyValue $CustomerID $PropertyName $ValueToInsert) -split ","
		}

		## Refresh empty List
		If(!$ValueList){
			$ValueList = @()
		}

		## Add the new Value
		$ValueList += $ValueToInsert.Trim()

		## Sort, Convert and Save
		$ReturnData = ($ValueList | Sort-Object ) -join ","
		## Write data back to DeviceProperty
		Set-NCCustomerProperty $CustomerID $PropertyName $ReturnData
	}
	End{
		## Return new values
		$ReturnData | 
		Write-Output
	}
}

Function Remove-NCCustomerPropertyValue{
	<#
	.Synopsis
	The Value is removed from the comma-separated string of unique values in the Customer Property.
	
	.Description
	The Value is removed from the comma-separated string of unique values in the Customer Property.
	Case-sensivity is optional.

	
	#>
		[CmdletBinding()]
	
		Param(
			[Parameter(Mandatory=$true,
	#               ValueFromPipeline = $true,
					ValueFromPipelineByPropertyName = $true,
					Position = 0,
					HelpMessage = 'Existing Customer ID')]
			[int]$CustomerID,
				
			[Parameter(Mandatory=$true,
	#               ValueFromPipeline = $true,
					ValueFromPipelineByPropertyName = $true,
					Position = 1,
					HelpMessage = 'Existing Property (name)')]
				[Alias("PropertyLabel","Property","CustomProperty")]
			[string]$PropertyName,

			[Parameter(Mandatory=$true,
	#               ValueFromPipeline = $true,
					ValueFromPipelineByPropertyName = $true,
					Position = 2,
					HelpMessage = 'Value to Remove from the String')]
				[Alias("Value")]
			[string]$ValueToDelete,

			[Parameter(Mandatory=$false,
				HelpMessage = 'Preserve Case')]
				[Alias('UseCase')]
			[Switch]$CaseSensitive,

			[Parameter(Mandatory=$false)]$NcSession
		)
		
		Begin{
			#check parameters. Use defaults if needed/available
			If (!$NcSession){
				If (-not (NcConnected)){
					Break
				}
				$NcSession = $Global:_NCSession
			}
		}

		Process{
			$ReturnData = $null
			[system.collections.arraylist]$ValueList = (Get-NCCustomerProperty $CustomerID $PropertyName) -split ","

			## Check if values are retrieved
			If($ValueList){
				If ($CaseSensitive){
					$ValueList.remove($ValueToDelete)
				}
				Else{
					$ValueList =$ValueList.Where{$_ -ne "$ValueToDelete"}
					#$ValueList =$ValueList | Where-Object -FilterScript {$_ -ne "$ValueToDelete"}
				}
				$ReturnData = ( $ValueList | Sort-Object ) -join ","

				## Write data back to DeviceProperty
				Set-NCCustomerProperty $CustomerID $PropertyName $ReturnData
			}
		}
		End{
			$ReturnData | 
			Write-Output
		}
}

Function Backup-NCCustomProperties{
	<#
	.Synopsis
	Backup CustomProperties to a file. Customer or Device. WIP
	
	.Description
	Backup CustomProperties to a file. Customer or Device.
	PathName must be supplied.
	Work In Progress. Currently Customer-Data only.
	

	#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 0,
				HelpMessage = 'Existing Customer ID')]
			[Alias("IDs")]
		[array]$CustomerID,

		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 1,
				HelpMessage = 'Name of the Backup Path')]
			[Alias("Path")]
		[String]$BackupPath,
			
		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		
		#Valid Path / sufficient rights
		$DateID =(get-date).ToString(‘yyyyMMdd’)
		$ExportFile = ("{0}\Backup_{1}.json" -f $BackupPath,$DateId)

		## [System.IO.File]::Exists($ExportFile)
		## Test-Path $ExportFile -PathType Leaf
		If(Test-Path $ExportFile -PathType Leaf){
			Write-Warning "File already existed"
			Remove-Item -Path $ExportFile -Force
		}


		$ReturnData = $null

		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}
	Process{
		Write-Host "Backup-NCCustomerProperties - Work in Progress"
		Write-host ("Exporting data for Customer {0} to file {1}" -f $CustomerID,$ExportFile)

		## Add information about the backup
		$BUHeader = @{}
		$BUHeader.Date = $DateID
		$BUHeader.Customer = $CustomerID


		## Convert list of ObJects to Array/hash
		$Data = Get-NCCustomerPropertyList $CustomerID

		$BUHeader.Data = $Data

		($BUHeader | ConvertTo-Json -depth 10).tostring() | Out-File $ExportFile -NoClobber -Force

<#		
		## Differentiate between Standard(Customer) and Custom(Organization) properties. --> No
		If ($CustomerProperty){
			#$this.CustomerPropertyValue($CustomerID,"CustomerName")
			$ReturnData = $NcSession.CustomerPropertyValue($CustomerID,$PropertyLabel)
		}
		Else{
			$ReturnData = ($NcSession.OrganizationPropertyList($CustomerID)).$PropertyLabel
		}
#>
	}
	End{

		$Returndata |
		Write-Output
	}
}


Function Get-NCProbeList{
<#
.Synopsis
Returns the Probes for the given CustomerID(s).

.Description
Returns the Probes for the given CustomerID(s).
If no customerIDs are supplied, all probes will be returned.

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
               ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 0,
               HelpMessage = 'Existing Customer ID')]
			[Alias("CustomerID")]
		[Array]$CustomerIDs,

		[Parameter(Mandatory=$false)]$NcSession
	)
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
		If (!$CustomerIDs){
			If (!$NcSession.DefaultCustomerID){
				Write-Host "No CustomerID specified."
				Break
			}
			$CustomerIDs = $NcSession.DefaultCustomerID
			Write-Host ("Using current default CustomerID {0} for NCProbeList." -f $CustomerIDs)
		}
	}
	Process{
		ForEach ($CustomerID in $CustomerIDs){
			$NcSession.DeviceList($CustomerID,$false,$true)|
			Select-Object deviceid,@{n="customerid"; e={$CustomerID}},customername,longname,url,* -ErrorAction SilentlyContinue |
			Write-Output 
		}
	}
	End{
	}

}
#EndRegion

#Region Devices
Function Get-NCDeviceList{
<#
.Synopsis
Returns the Managed Devices for the given CustomerID(s) and Sites below.

.Description
Returns the Managed Devices for the given CustomerID(s) and Sites below.
If no customerIDs are supplied, all managed devices will be returned.

## TODO - Confirmation if no CustomerID(s) are supplied (Full List).
#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
               #ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 0,
               HelpMessage = 'Existing Customer ID')]
			[Alias("customerid")]
		[array]$CustomerIDs,

		[Parameter(Mandatory=$false,
			HelpMessage = 'No Sorting of the output')]
			[Alias('UnSorted')]
		[Switch]$NoSort,

		[Parameter(Mandatory=$false)]$NcSession
	)
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
		If (!$CustomerIDs){
			If (!$NcSession.DefaultCustomerID){
				Write-Host "No CustomerID specified."
				Break
			}
			$CustomerIDs = $NcSession.DefaultCustomerID
			Write-Host ("Using current default CustomerID {0} for NCDeviceList." -f $CustomerIDs)
		}
	}
	Process{
		ForEach ($CustomerID in $CustomerIDs){
			#Write-host ("CustomerID = {0}." -f $CustomerID)
			$ReturnData = $NcSession.DeviceList($CustomerID)

			If($NoSort){
				$ReturnData | Write-Output
			}
			Else{
				## Alphabetical Columnnames
				$ReturnData | Select-Object ($ReturnData|Get-Member -type Noteproperty -ErrorAction SilentlyContinue).name -ErrorAction SilentlyContinue |
				## CustomerID is not returned by default. Added as custom field.
				Select-Object deviceid,@{n="customerid"; e={$CustomerID}},customername,sitename,longname,uri,* -ErrorAction SilentlyContinue |
				Write-Output
			}
		}
	}
	End{
	}
}

Function Get-NCDeviceID{
	<#
	.Synopsis
	Returns the DeviceID(s) for the given DeviceName(s). Case Sensitive, No Wildcards.

	.Description
	The returned objects contain extra information for verification.
	The supplied name(s) are Case Sensitive, No Wildcards allowed. 
	Also not-managed devices are returned.
	Nothing is returned for names not found.
	
	#>
	
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$true,
               ValueFromPipeline = $true,
#               ValueFromPipelineByPropertyName = $true,
               Position = 0,
               HelpMessage = 'Array of existing Filter IDs')]
#			[Alias("Name")]
		[Array]$DeviceNames,
		
		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
		If (!$DeviceNames){
			Write-Host "No DeviceName(s) given."
			Break
		}
	}
	Process{
		## Collect the data for all Names. Case Sensitive, No Wildcards.
		## Only Returns found devices.
				
		ForEach ($DeviceName in $DeviceNames){
			## Use the NameFilter of the DevicePropertyList to find the DeviceID for now.
			## Limited Filter-options, but fast.
			$NcSession.DevicePropertyList($null,$DeviceName,$null,$null) |
			## Add additional Info and return only selected fields/Columns
			Get-NCDeviceInfo |
			Select-Object DeviceID,LongName,DeviceClass,CustomerID,CustomerName,IsManagedAsset |
			Write-Output 
		}
	
	}
	End{
	}
}

Function Get-NCDeviceLocal{
	<#
	.Synopsis
	Returns the DeviceID, CustomerID and some more Info for the Local Computer.

	.Description
	Queries the local ApplicationID and returns the NCentral DeviceID.
	No Parameters recquired.
	
	#>
	
	[CmdletBinding()]

	Param(
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
        $ApplianceConfig = ("{0}\N-able Technologies\Windows Agent\config\ApplianceConfig.xml" -f ${Env:ProgramFiles(x86)})
        $ServerConfig = ("{0}\N-able Technologies\Windows Agent\config\ServerConfig.xml" -f ${Env:ProgramFiles(x86)})

		If (-not (Test-Path $ApplianceConfig -PathType leaf)){
			Write-Host "No Local NCentral-agent Configuration found."
			Write-Host "Try using 'Get-NCDeviceID $Env:ComputerName'."
			Break
		}
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}
	Process{
        # Get appliance id
        $ApplianceXML = [xml](Get-Content -Path $ApplianceConfig)
        $ApplianceID = $ApplianceXML.ApplianceConfig.ApplianceID
		# Get management Info.
        $ServerXML = [xml](Get-Content -Path $ServerConfig)
		$ServerIP = $ServerXML.ServerConfig.ServerIP
		$ConnectIP = $NcSession.ConnectionURL

		If($ServerIP -ne $ConnectIP){
			Write-Host "The Local Device is Managed by $ServerIP. You are connected to $ConnectIP."
		}
		
		$NcSession.DeviceGetAppliance($ApplianceID)|
		## Return all Info, since already collected.
		Select-Object deviceid,longname,@{Name="managedby"; Expression={$ServerIP}},customerid,customername,deviceclass,licensemode,* -ErrorAction SilentlyContinue |
		Write-Output
	}
	End{
	}
}

Function Get-NCDevicePropertyList{
<#
.Synopsis
Returns the Custom Properties of the DeviceID(s).

.Description
Returns the Custom Properties of the DeviceID(s).
If no devviceIDs are supplied, all managed devices
and their Custom Properties will be returned.

## TODO - Confirmation if no DeviceID(s) are supplied (Full List). Only warning now.
## Issue: Only properties of first item are added/displayed for all Devices in a list.
#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
               #ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 0,
               HelpMessage = 'Existing Device ID')]
			[Alias("DeviceID")]
		[Array]$DeviceIDs,
			
		[Parameter(Mandatory=$false,
			HelpMessage = 'No Sorting of the output')]
			[Alias('UnSorted')]
		[Switch]$NoSort,

		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}
	Process{
		#Write-Host $DeviceIDs
		If ($DeviceIDs){

			foreach($DeviceId in $DeviceIDs){
				$Propertydata = $NcSession.DevicePropertyList($DeviceID,$null,$null,$null)
				$ReturnData += $Propertydata
			}
			#$Returndata = $NcSession.DevicePropertyList($DeviceIDs,$null,$null,$null)

		}
		Else{
			Write-Host "Generating a full DevicePropertyList may take some time."
			
			$ReturnData = $NcSession.DevicePropertyList($null,$null,$null,$null)

			Write-Host "Data retrieved, processing output."
		}
	}
	End{
		If ($NoSort){
			$ReturnData | Write-Output
		}
		Else{
			## Determine all unique colums over all items. Columns can vary per asset-class.
			[System.Collections.ArrayList]$AllColumns=@()
			
			$counter = $Returndata.length
			for ($i=0; $i -lt $counter ; $i ++){
				$Names = ($ReturnData[$i] |Get-Member -type Noteproperty -ErrorAction SilentlyContinue).name

				$counter2 = $names.count
				for ($j=0; $j -lt $counter2 ; $j ++){
					$AllColumns += $names[$j]
					#Write-Host ("Counter {0} has value {1}." -f $j,$names[$j])
				}
				## putting this line here might preserve memory
				$AllColumns = $AllColumns | Sort-Object -Unique
			}
			## This is the alternative position to make entries unique
			#$AllColumns = $AllColumns | Sort-Object -Unique
			#Write-host $AllColumns			## for debugging

			$ReturnData | 
			## Alphabetical Columnnames		## Issue: Only properties of first item are added/displayed for all Devices in a list.
			Select-Object $AllColumns |
			#Select-Object ($ReturnData|Get-Member -type Noteproperty -ErrorAction SilentlyContinue).name -ErrorAction SilentlyContinue |

			## Make DeviceID the first column.
			Select-Object deviceid,* -ErrorAction SilentlyContinue |
			Write-Output
		}
	}
}

Function Get-NCDevicePropertyListFilter{
<#
.Synopsis
Returns the Custom Properties of the Devices within the FilterID(s).

.Description
Returns the Custom Properties of the Devices within the FilterID(s).
A filterID must be supplied. Hoover over the filter in the GUI to reveal its ID.

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$true,
               ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 0,
               HelpMessage = 'Array of existing Filter IDs')]
			[Alias("FilterID")]
		[Array]$FilterIDs,
		
		[Parameter(Mandatory=$false,
			HelpMessage = 'No Sorting of the output')]
			[Alias('UnSorted')]
		[Switch]$NoSort,

		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
		If (!$FilterIDs){
			Write-Host "No FilterIDs given."
			Break
		}
	}
	Process{
		#Collect the data for all IDs.
		
		ForEach ($FilterID in $FilterIDs){
			$ReturnData = $NcSession.DevicePropertyList($null,$null,$FilterID,$null)

			If($NoSort){
				$ReturnData | Write-Output
			}
			Else{
				## Alphabetical Columnnames
				$ReturnData | Select-Object ($ReturnData|Get-Member -type Noteproperty -ErrorAction SilentlyContinue).name -ErrorAction SilentlyContinue |
				## Make DeviceID the first column.
				Select-Object deviceid,* -ErrorAction SilentlyContinue |
				Write-Output
			}

		}
	
	}
	End{
	}
}

Function Set-NCDeviceProperty{
	<#
	.Synopsis
	Set the value of the Custom Property for the DeviceID(s). Base64 optional.
	
	.Description
	Set the value of the Custom Property for the DeviceID(s).
	Existing values are overwritten, Properties are cleared if no Value is supplied.
	Optional Base64 Encoding (Unicode/UTF16).
	
	#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 0,
				HelpMessage = 'Existing Device IDs')]
			[Alias("DeviceID")]
		[Array]$DeviceIDs,

		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
#               ValueFromPipelineByPropertyName = $true,
				Position = 1,
				HelpMessage = 'Name of the Device Custom-Property')]
				[Alias("PropertyName")]
			[String]$PropertyLabel,

		[Parameter(Mandatory=$false,
#               ValueFromPipeline = $true,
#               ValueFromPipelineByPropertyName = $true,
				Position = 2,
				HelpMessage = 'Value for the Device Custom-Property or empty')]
				[Alias("Value")]
			[String]$PropertyValue,
		
		[Parameter(Mandatory=$false,
				HelpMessage = 'Encode the PropertyValue')]
				[Alias("Encode")]
			[Switch]$Base64,
					
		[Parameter(Mandatory=$false,		## Optional with $Base64
			HelpMessage = 'Use UTF8 Encoding iso UniCode')]
		[Switch]$UTF8,
			
		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
#		If (!$DeviceIDs){
#			## Issue when value comes from pipeline. Use Parameter-validation.
#			Write-Host "No DeviceID specified."
#			Break
#		}
#		If (!$PropertyLabel){
#			## Use Parameter-validation.
#			Write-Host "No Property-name specified."
#			Break
#		}
		If (!$PropertyValue){
			#Write-Host "DeviceProperty '$PropertyLabel' will be cleared."
			$PropertyValue=$null
		}
	}
	Process{
		## Encode if requested
		If ($Base64){
			$PropertyValue = $NCSession.ConvertBase64($PropertyValue,$false,$UTF8)
		}

		ForEach($DeviceID in $DeviceIDs ){
			$NcSession.DevicePropertyModify($DeviceID, $PropertyLabel, $PropertyValue)
		}
	}
	End{
	}
}

Function Get-NCDeviceProperty{
	<#
	.Synopsis
	Returns the Value of the Custom Device Property. Base64 optional.
	
	.Description
	Returns the Value of the Custom Device Property.
	(Save) Base64 decoding optional.
	
	#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 0,
				HelpMessage = 'Existing Device ID')]
			[Alias("ID")]
		[int]$DeviceID,
			
		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 1,
				HelpMessage = 'Existing Property')]
			[Alias("Property","CustomProperty")]
		[string]$PropertyName,
			
		[Parameter(Mandatory=$false,
			HelpMessage = 'Decode the PropertyValue if needed')]
			[Alias("Decode")]
		[Switch]$Base64,
		
		[Parameter(Mandatory=$false,		## Optional with $Base64
			HelpMessage = 'Use UTF8 Encoding iso UniCode')]
		[Switch]$UTF8,
			
		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}
	Process{
		$ReturnData = ($NcSession.DevicePropertyList($DeviceID,$null,$null,$null).$PropertyName)

		## Decode if requested
		If($Base64){
			If($ReturnData){
				$ReturnData = $NCSession.ConvertBase64($ReturnData,$true,$UTF8)
			}
		}
	}
	End{
		$ReturnData |
		Write-Output	
	}
#>
}

Function Add-NCDevicePropertyValue{
	<#
	.Synopsis
	The Value is added to the comma-separated string of unique values in the Custom Device Property.
	
	.Description
	The Value is added to the comma-separated string of unique values in the Custom Device Property.
	Case-sensivity is optional.

	
	#>
		[CmdletBinding()]
	
		Param(
			[Parameter(Mandatory=$true,
	#               ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 0,
				   HelpMessage = 'Existing Device ID')]
			[int]$DeviceID,
				
			[Parameter(Mandatory=$true,
	#               ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 1,
				   HelpMessage = 'Existing Property')]
				[Alias("PropertyLabel","Property","CustomProperty")]
			[string]$PropertyName,

			[Parameter(Mandatory=$true,
	#               ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 2,
				   HelpMessage = 'Value to Add to the String')]
				[Alias("Value")]
			[string]$ValueToInsert,

			[Parameter(Mandatory=$false,
				HelpMessage = 'Preserve Case')]
				[Alias('UseCase')]
			[Switch]$CaseSensitive,

			[Parameter(Mandatory=$false)]$NcSession
		)
		
		Begin{
			#check parameters. Use defaults if needed/available
			If (!$NcSession){
				If (-not (NcConnected)){
					Break
				}
				$NcSession = $Global:_NCSession
			}
		}
		Process{
			## Retrieve Existing values
			#[system.collections.arraylist]$ValueList = (Get-NCDeviceProperty $DeviceID $PropertyName) -split ","

			## Remove Existing
			If ($CaseSensitive){
				[system.collections.arraylist]$ValueList = (Remove-NCDevicePropertyValue $DeviceID $PropertyName $ValueToInsert -UseCase) -split ","
			}
			Else{
				[system.collections.arraylist]$ValueList = (Remove-NCDevicePropertyValue $DeviceID $PropertyName $ValueToInsert) -split ","
			}

			## Refresh empty List
			If(!$ValueList){
				$ValueList = @()
			}

			## Add the new Value
			$ValueList += $ValueToInsert.Trim()
<#
			## Remove duplicate values. Is applied to existing values also. 
			If ($CaseSensitive){
				$ReturnData = ($ValueList | Select-Object -Unique |Sort-Object) -join ","
				#$ReturnData = ($ValueList | Get-Unique -AsString | Sort-Object) -join ","
			}
			Else{
				$ReturnData = ($ValueList | Sort-Object -Unique ) -join ","
			}
#>
			## Sort, Convert and Save
			$ReturnData = ($ValueList | Sort-Object ) -join ","
			## Write data back to DeviceProperty
			Set-NCDeviceProperty $DeviceID $PropertyName $ReturnData
		}
		End{
			## Return new values
			$ReturnData | 
			Write-Output
		}
}

Function Remove-NCDevicePropertyValue{
	<#
	.Synopsis
	The Value is removed from the comma-separated string of unique values in the Custom Device Property.
	
	.Description
	The Value is removed from the comma-separated string of unique values in the Custom Device Property.
	Case-sensivity is optional.

	
	#>
		[CmdletBinding()]
	
		Param(
			[Parameter(Mandatory=$true,
	#               ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 0,
				   HelpMessage = 'Existing Device ID')]
			[int]$DeviceID,
				
			[Parameter(Mandatory=$true,
	#               ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 1,
				   HelpMessage = 'Existing Property')]
				[Alias("Property","CustomProperty")]
			[string]$PropertyName,

			[Parameter(Mandatory=$true,
	#               ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 2,
				   HelpMessage = 'Value to Remove from the String')]
				[Alias("Value")]
			[string]$ValueToDelete,

			[Parameter(Mandatory=$false,
				HelpMessage = 'Preserve Case')]
				[Alias('UseCase')]
			[Switch]$CaseSensitive,

			[Parameter(Mandatory=$false)]$NcSession
		)
		
		Begin{
			#check parameters. Use defaults if needed/available
			If (!$NcSession){
				If (-not (NcConnected)){
					Break
				}
				$NcSession = $Global:_NCSession
			}
		}

		Process{
			$ReturnData = $null
			[system.collections.arraylist]$ValueList = (Get-NCDeviceProperty $DeviceID $PropertyName) -split ","

			## Check if values are retrieved
			If($ValueList){
				If ($CaseSensitive){
					$ValueList.remove($ValueToDelete)
				}
				Else{
					$ValueList =$ValueList.Where{$_ -ne "$ValueToDelete"}
					#$ValueList =$ValueList | Where-Object -FilterScript {$_ -ne "$ValueToDelete"}
				}
				$ReturnData = ( $ValueList | Sort-Object ) -join ","

				## Write data back to DeviceProperty
				Set-NCDeviceProperty $DeviceID $PropertyName $ReturnData
			}
		}
		End{
			$ReturnData | 
			Write-Output
		}
}

Function Get-NCDeviceInfo{
<#
.Synopsis
Returns the General details for the DeviceID(s).

.Description
Returns the General details for the DeviceID(s).
DeviceID(s) must be supplied, as a parameter or by PipeLine.
Use Get-NCDeviceObject tot retrieve ALL details of a device.

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 0,
				HelpMessage = 'Existing Device IDs')]
#			[ValidateScript({ $_ | ForEach-Object {(Get-Item $_).PSIsContainer}})]
			[Alias("DeviceID")]
		[Array]$DeviceIDs,
		
		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}
	Process{
		#Collect the data for all given IDs.
		ForEach ($DeviceID in $DeviceIDs){
			$NcSession.DeviceGet($DeviceID)|
			Select-Object deviceid,longname,customerid,customername,deviceclass,licensemode,* -ErrorAction SilentlyContinue |
			Write-Output
		}
	}
	End{
	}
}
	
Function Get-NCDeviceObject{
<#
.Synopsis
Returns a Device and all asset-properties as an object.

.Description
Returns a Device and all asset-properties as an object.
The asset-properties may contain multiple entries.

#>

<#
Work in Progress. Calls Ncentral_Connection.DeviceAssetInfoExportWithSettings
Returns information as an [Array of] Multi-dimentional object(s) with array Properties.

ToDo: Options to Include/Exclude properties from the N-Central query.
		Needed for Speed/Performance improvement.
	
#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 0,
				HelpMessage = 'Existing Device IDs')]
#			[ValidateScript({ $_ | ForEach-Object {(Get-Item $_).PSIsContainer}})]
			[Alias("DeviceID")]
		[Array]$DeviceIDs,
		
		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}
	Process{
		#Collect the data for all IDs.
		ForEach ($DeviceID in $DeviceIDs){
			$NcSession.DeviceAssetInfoExportDeviceWithSettings($DeviceID)|	
			# Put General properties in front.
#			Select-Object deviceid,longname,customerid,deviceclass,* -ErrorAction SilentlyContinue |
			Write-Output
		}
	}
	End{

	}
}
#EndRegion

#Region Services and Tasks
Function Get-NCActiveIssuesList{
<#
.Synopsis
Returns the Active Issues on the CustomerID-level and below.

.Description
Returns the Active Issues on the CustomerID-level and below.
An additional Search/Filter-string can be supplied.

If no customerID is supplied, Default Customer is used.
The SiteID of the devices is returned (Not CustomerID).

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
               #ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 0,
               HelpMessage = 'Existing Customer ID')]
		[Int]$CustomerID,

		[Parameter(Mandatory=$false,
               ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 1,
               HelpMessage = 'Text to look for')]
		[String]$IssueSearchBy = "",

		[Parameter(Mandatory=$false,
               ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 2,
               HelpMessage = 'Status Code')]
		[Int]$IssueStatus = 0,

		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
		If (!$CustomerID){
			If (!$NcSession.DefaultCustomerID){
				Write-Host "No CustomerID specified."
				Break
			}
			$CustomerID = $NcSession.DefaultCustomerID
			Write-Host ("Using current default CustomerID {0} for NCActiveIssuesList." -f $CustomerID)
		}
	}
	Process{
		$ReturnData = $NcSession.ActiveIssuesList($CustomerID, $IssueSearchBy, $IssueStatus)
	}
	End{
		$ReturnData |
		## Alphabetical Columnnames
		Select-Object ($ReturnData|Get-Member -type Noteproperty -ErrorAction SilentlyContinue).name -ErrorAction SilentlyContinue |
		## Put important fields in front.
		Select-Object taskid,@{n="siteid"; e={$_.CustomerID}},CustomerName,DeviceID,DeviceName,DeviceClass,ServiceName,NotifState,TransitionTime,* -ErrorAction SilentlyContinue |
#		Sort-Object TransitionTime -Descending | Select-Object @{n="SiteID"; e={$_.CustomerID}},CustomerName,DeviceID,DeviceName,DeviceClass,ServiceName,TransitionTime,NotifState,* -ErrorAction SilentlyContinue |
		Write-Output



	}
}

Function Get-NCJobStatusList{
	<#
	.Synopsis
	Returns the Scheduled Jobs on the CustomerID-level and below.
	
	.Description
	Returns the Scheduled Jobs on the CustomerID-level and below.
	Including Discovery Jobs
		
	If no customerID is supplied, all Jobs are returned.
	The SiteID of the devices is returned (Not CustomerID).
	
	#>
		[CmdletBinding()]
	
		Param(
			[Parameter(Mandatory=$false,
				   #ValueFromPipeline = $true,
				   ValueFromPipelineByPropertyName = $true,
				   Position = 0,
				   HelpMessage = 'Existing Customer ID')]
			[Int]$CustomerID
		)
		
		Begin{
			#check parameters. Use defaults if needed/available
			If (!$NcSession){
				If (-not (NcConnected)){
					Break
				}
				$NcSession = $Global:_NCSession
			}
			If (!$CustomerID){
				If (!$NcSession.DefaultCustomerID){
					Write-Host "No CustomerID specified."
					Break
				}
				$CustomerID = $NcSession.DefaultCustomerID
				Write-Host ("Using current default CustomerID {0} for NCJobStatusList." -f $CustomerID)
			}
		}
		Process{
			$NcSession.JobStatusList($CustomerID)|
			Select-Object CustomerID,CustomerName,DeviceID,DeviceName,DeviceClass,JobName,ScheduledTime,* -ErrorAction SilentlyContinue |
	#		Sort-Object ScheduledTime -Descending | Select-Object @{n="SiteID"; e={$_.CustomerID}},CustomerName,DeviceID,DeviceName,DeviceClass,ServiceName,TransitionTime,NotifState,* -ErrorAction SilentlyContinue |
			Write-Output
		}
		End{
		}
}

Function Get-NCDeviceStatus{
<#
.Synopsis
Returns the Services for the DeviceID(s).

.Description
Returns the Services for the DeviceID(s).
DeviceID(s) must be supplied, as a parameter or by PipeLine.

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$true,
#               ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 0,
               HelpMessage = 'Existing Device IDs')]
			[Alias("DeviceID")]
		[Array]$DeviceIDs,
		
		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}
	Process{
		ForEach($DeviceID in $DeviceIDs){
			$NcSession.DeviceGetStatus($DeviceID)|
			Select-Object deviceid,devicename,serviceid,modulename,statestatus,transitiontime,* -ErrorAction SilentlyContinue |
			Write-Output
		}
	}
	End{
	}
}
#EndRegion

#Region Access Control
Function Get-NCAccessGroupList{
<#
.Synopsis
Returns the list of AccessGroups at the specified CustomerID level.

.Description
Returns the list of AccessGroups at the specified CustomerID level.

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
               #ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 0,
			HelpMessage = 'Existing Customer IDs')]
			[Alias("customerid")]
		[array]$CustomerIDs,
	   		
		[Parameter(Mandatory=$false,
			HelpMessage = 'Return only used AccessGroups')]
			[Alias("UsedOnly")]
		[Switch]$Filter,

		[Parameter(Mandatory=$false,
			HelpMessage = 'No Sorting of the output columns')]
			[Alias('UnSorted')]
		[Switch]$NoSort,

		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
		If (!$CustomerIDs){
			If (!$NcSession.DefaultCustomerID){
				Write-Host "No CustomerID specified."
				Break
			}
			$CustomerIDs = $NcSession.DefaultCustomerID
			Write-Host ("Using current default CustomerID {0} for NCAccessGroupList." -f $CustomerIDs)
		}
	}
	Process{
		$ReturnData = @()
		ForEach($CustomerID in $customerIDs){
			#Write-Output $NcSession.AccessGroupList($CustomerID)
			$ReturnData += $NcSession.AccessGroupList($CustomerID)
			# |	Where-Object {$_.customerid -eq $Customerid}
		}
		## Return only used groups.
		If($Filter){
			$Returndata = $Returndata | Where-object {$_.usernames -ne "[]"}
		}
	}
	End{
		If($NoSort){
			$ReturnData | Write-Output
		}
		Else{
			## Alphabetical Columnnames
			$ReturnData | Select-Object ($ReturnData|Get-Member -type Noteproperty -ErrorAction SilentlyContinue).name -ErrorAction SilentlyContinue |
			## Important fields in front. ToDo: Boolean customergroup, derived from groupType.
			Select-Object groupid,grouptype,customerid,groupname,* -ErrorAction SilentlyContinue |
			Write-Output
		}
	}
}
Function Get-NCAccessGroupDetails{
<#
.Synopsis
Returns the details of the specified (CustomerAccess) GroupID.

.Description
Returns the details of the specified (CustomerAccess) GroupID.

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$true,
				#ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 0,
				HelpMessage = 'Existing Group IDs')]
				[Alias("groupid")]
			[array]$GroupIDs,
				
		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$GroupIDs){
			Write-Host "No GroupID specified."
			Break
		}
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	Write-host $Groupids
	If (!$GroupIDs){
			Write-Host "No GroupID specified."
			Break
		}
	}
	Process{
		$ReturnData = @()
		ForEach($GroupID in $GroupIDs){
			## Only Customer-AccessGroups. ToDo: Implement DeviceGroups (now error: 4100 Invalid parameters)
			$ReturnData += $NcSession.AccessGroupGet($GroupID)
		}
	}
	End{
		$ReturnData | Write-Output
	}
}
	
Function Get-NCUserRoleList{
<#
.Synopsis
Returns the list of Roles at the specified CustomerID level.

.Description
Returns the list of Roles at the specified CustomerID level.

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
               #ValueFromPipeline = $true,
               ValueFromPipelineByPropertyName = $true,
               Position = 0,
			HelpMessage = 'Existing Customer IDs')]
			[Alias("customerid")]
		[array]$CustomerIDs,

		[Parameter(Mandatory=$false,
			HelpMessage = 'Return only used Roles')]
			[Alias("UsedOnly")]
		[Switch]$Filter,

		[Parameter(Mandatory=$false,
			HelpMessage = 'No Sorting of the output colums')]
			[Alias('UnSorted')]
		[Switch]$NoSort,

		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
		If (!$CustomerIDs){
			If (!$NcSession.DefaultCustomerID){
				Write-Host "No CustomerID specified."
				Break
			}
			$CustomerIDs = $NcSession.DefaultCustomerID
			Write-Host ("Using current default CustomerID {0} for NCUserRoleList." -f $CustomerIDs)
		}
	}
	Process{
		$Returndata = @()
		ForEach($CustomerID in $CustomerIDs){
			#Write-Output $NcSession.UserRoleList($CustomerID)
			## Customerid is not returned inside the query-result.
			$ReturnData += $NcSession.UserRoleList($CustomerID) |
							Select-Object @{n="customerid"; e={$customerid}},
										* -ErrorAction SilentlyContinue 
		}
		## All-parameter NOT provided returns only filtered results.
		If($Filter){
			$Returndata = $Returndata | Where-object {$_.usernames -ne "[]"}
		}
	}
	End{
		If($NoSort){
			$ReturnData | Write-Output
		}
		Else{
			## Alphabetical Columnnames
			$ReturnData | Select-Object ($ReturnData|Get-Member -type Noteproperty -ErrorAction SilentlyContinue).name -ErrorAction SilentlyContinue |
			## Important fields in front. ToDo: Boolean customergroup, derived from groupType.
			Select-Object roleid,readonly,customerid,rolename,* -ErrorAction SilentlyContinue |
			Write-Output
		}
	}
}

Function Get-NCUserRoleDetails{
<#
.Synopsis
Returns the Details of the specified RoleID.

.Description
Returns the Details of the specified RoleID.

#>
	[CmdletBinding()]

	Param(
		[Parameter(Mandatory=$false,
				#ValueFromPipeline = $true,
				ValueFromPipelineByPropertyName = $true,
				Position = 0,
				HelpMessage = 'Existing Role IDs')]
				[Alias("roleid")]
		[array]$RoleIDs,

		[Parameter(Mandatory=$false)]$NcSession
	)
	
	Begin{
		#check parameters. Use defaults if needed/available
		If (!$RoleIDs){
			Write-Host "No RoleID specified."
			Break
		}
		If (!$NcSession){
			If (-not (NcConnected)){
				Break
			}
			$NcSession = $Global:_NCSession
		}
	}
	Process{
		$Returndata = @()
		ForEach($RoleID in $RoleIDs){
			#Write-Output $NcSession.UserRoleGet($RoleID)
			$ReturnData +=  $NcSession.UserRoleGet($RoleID)
		}
	}
	End{
		$ReturnData | Write-Output
	}
}
#EndRegion

#EndRegion

#Region Module management
# Best practice - Export the individual Module-commands.
Export-ModuleMember -Function Get-NCHelp,
Convert-Base64,
Format-Properties,
NcConnected,
New-NCentralConnection,
Get-NCTimeOut,
Set-NCTimeOut,
Get-NCServiceOrganizationList,
Get-NCCustomerList,
Set-NCCustomerDefault,
Get-NCCustomerPropertyList,
Set-NCCustomerProperty,
Get-NCCustomerProperty,
Add-NCCustomerPropertyValue,
Remove-NCCustomerPropertyValue,
Get-NCProbeList,
Get-NCJobStatusList,
Get-NCDeviceList,
Get-NCDeviceID,
Get-NCDeviceLocal,
Get-NCDevicePropertyList,
Get-NCDevicePropertyListFilter,
Set-NCDeviceProperty,
Get-NCDeviceProperty,
Add-NCDevicePropertyValue,
Remove-NCDevicePropertyValue,
Get-NCActiveIssuesList,
Get-NCDeviceInfo,
Get-NCDeviceObject,
Get-NCDeviceStatus,
Get-NCAccessGroupList,
Get-NCAccessGroupDetails,
Get-NCUserRoleList,
Get-NCUserRoleDetails,
Backup-NCCustomProperties,
Get-NCVersion

Write-Debug "Module PS-NCentral loaded"

#EndRegion
