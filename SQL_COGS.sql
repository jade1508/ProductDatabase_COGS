/*The purpose of this project is to:
1. collect all types of expenses from other tables and calculate COGS of all products.
2. have deep insight into product portfolio of company.

There are two lines of coffee products: Single flavor and mixed flavors (combines various single ones in one pack)*/


--CALCULATE COGS

--0. Add new columns for Product Database
alter table ProductDatabase
add PurchaseSource nvarchar(50),
	ProcurementCost float,
	LabourCost float,
	WarehouseCost float, 
	AdminCost float, 
	PackagingCost float,
	PurchasePricePerUnit float, 
	PurchaseVAT float,
	PurchasePrice float

--1. Identify Suppliers
update ProductDatabase
set ProductDatabase.PurchaseSource = Purchasing.Source
	from ProductDatabase join Purchasing
	on ProductDatabase.INTERNAL_CODE_IMP = Purchasing.COMPANY_IDENTIFIER_OR_EAN_13_Digit_OR_UNIQUE_CODE_10_Digit

update ProductDatabase
set ProductDatabase.PurchaseSource = Purchasing_Mix.Supplier
	from ProductDatabase join Purchasing_Mix
	on ProductDatabase.INTERNAL_CODE_IMP = Purchasing_Mix.[PARENT_CODE]

--2. Calculate Procurement Cost
update ProductDatabase 
set ProductDatabase.ProcurementCost = ProcurementCost_UK.PROCUREMENT_COST
	from ProductDatabase join ProcurementCost_UK
	on ProductDatabase.PurchaseSource = ProcurementCost_UK.SUPPLIER

--3. Calculate Labour Cost
update ProductDatabase 
set ProductDatabase.LabourCost = LabourCost.Cost
	from ProductDatabase join LabourCost
	on ProductDatabase.[PACKAGING_TIME_MINS] = LabourCost.Time_to_pack_each_Unit_Mins

--4. Calculate Other Costs
update ProductDatabase 
set ProductDatabase.WarehouseCost = 
	(select Warehouse_Cost from OtherCosts),
	ProductDatabase.AdminCost = 
	(select Admin_Subscription_Cost from OtherCosts),
	ProductDatabase.PackagingCost = 
	(select Packaging_Cost from OtherCosts)

--5. Calculate Purchase Price Per Unit and VAT
update ProductDatabase 
set ProductDatabase.PurchaseVAT = Purchasing.Purchase_VAT,
	ProductDatabase.PurchasePricePerUnit = Purchasing.total_purchase_price_Excluding_VAT
	from ProductDatabase join Purchasing
	on ProductDatabase.INTERNAL_CODE_IMP = Purchasing.COMPANY_IDENTIFIER_OR_EAN_13_Digit_OR_UNIQUE_CODE_10_Digit

update ProductDatabase
set ProductDatabase.PurchaseVAT = Purchasing_Mix.VAT,
	ProductDatabase.PurchasePricePerUnit = Purchasing_Mix.TOTAL_PURCHASE_PRICE_EX_VAT
	from ProductDatabase join Purchasing_Mix
	on ProductDatabase.INTERNAL_CODE_IMP = Purchasing_Mix.PARENT_CODE

--6. Calculate COGS
update ProductDatabase
set PurchasePrice =  
	(PurchasePricePerUnit + ProcurementCost + LabourCost + WarehouseCost + AdminCost + PackagingCost) * (1 + PurchaseVAT)
from ProductDatabase


--ANALYZE PRODUCT PORTFOLIO

--1. Count number of products as per supplier
select PurchaseSource, count(ASIN) as NoofProducts
from ProductDatabase
group by PurchaseSource

--2. Count number of products as per category
select Amazon_Category, count(ASIN) as NoofProducts
from ProductDatabase
group by Amazon_Category

--3. Average purchase price as per %VAT
create function dbo.avg_purchase(@VAT_basis varchar(50))
returns float as

begin
	declare @avg_VAT float;
	select @avg_VAT = avg(PurchasePrice)
	from ProductDatabase
	where PurchaseVAT = @VAT_basis;
	return @avg_VAT
end

select dbo.avg_purchase(0) as AveragePrice_ZeroVAT
select dbo.avg_purchase(0.2) as AveragePrice_20PctVAT

--4. Grouping sets of single and mixed line per supplier
(
select p.Source as Supplier,
	   count (*) as count
from Purchasing p
group by p.Source
)
union all
(
select px.Supplier as Supplier,
	   count (*) as count
from Purchasing_Mix px
group by px.Supplier
)
order by 1

--5. Clean data and examine data quality
select count(
	cast((
	case when SUPPLIER_CODE is null or SUPPLIER_CODE in('')
		 then 1
		 else 0
	end) as float)) as missing_suppliercode
from Purchasing

--6. Figure out top 3 biggest suppliers
select top 3 PurchaseSource, sum(PurchasePrice) as totalamount
from ProductDatabase
group by PurchaseSource
having sum(PurchasePrice) > 500
order by PurchaseSource