local V2_TAG_NUMBER = 4

---@param v2Rankings ProviderProfileV2Rankings
---@return ProviderProfileSpec
local function convertRankingsToV1Format(v2Rankings, difficultyId, sizeId)
	---@type ProviderProfileSpec
	local v1Rankings = {}
	v1Rankings.progress = v2Rankings.progressKilled
	v1Rankings.total = v2Rankings.progressPossible
	v1Rankings.average = v2Rankings.bestAverage
	v1Rankings.spec = v2Rankings.spec
	v1Rankings.asp = v2Rankings.allStarPoints
	v1Rankings.rank = v2Rankings.allStarRank
	v1Rankings.difficulty = difficultyId
	v1Rankings.size = sizeId

	v1Rankings.encounters = {}
	for id, encounter in pairs(v2Rankings.encountersById) do
		v1Rankings.encounters[id] = {
			kills = encounter.kills,
			best = encounter.best,
		}
	end

	return v1Rankings
end

---Convert a v2 profile to a v1 profile
---@param v2 ProviderProfileV2
---@return ProviderProfile
local function convertToV1Format(v2)
	---@type ProviderProfile
	local v1 = {}
	v1.subscriber = v2.isSubscriber
	v1.perSpec = {}

	if v2.summary ~= nil then
		v1.progress = v2.summary.progressKilled
		v1.total = v2.summary.progressPossible
		v1.totalKillCount = v2.summary.totalKills
		v1.difficulty = v2.summary.difficultyId
		v1.size = v2.summary.sizeId
	else
		local bestSection = v2.sections[1]
		v1.progress = bestSection.anySpecRankings.progressKilled
		v1.total = bestSection.anySpecRankings.progressPossible
		v1.average = bestSection.anySpecRankings.bestAverage
		v1.totalKillCount = bestSection.totalKills
		v1.difficulty = bestSection.difficultyId
		v1.size = bestSection.sizeId
		v1.anySpec = convertRankingsToV1Format(bestSection.anySpecRankings, bestSection.difficultyId, bestSection.sizeId)
		for i, rankings in pairs(bestSection.perSpecRankings) do
			v1.perSpec[i] = convertRankingsToV1Format(rankings, bestSection.difficultyId, bestSection.sizeId)
		end
		v1.encounters = v1.anySpec.encounters
	end

	if v2.mainCharacter ~= nil then
		v1.mainCharacter = {}
		v1.mainCharacter.spec = v2.mainCharacter.spec
		v1.mainCharacter.average = v2.mainCharacter.bestAverage
		v1.mainCharacter.difficulty = v2.mainCharacter.difficultyId
		v1.mainCharacter.size = v2.mainCharacter.sizeId
		v1.mainCharacter.progress = v2.mainCharacter.progressKilled
		v1.mainCharacter.total = v2.mainCharacter.progressPossible
		v1.mainCharacter.totalKillCount = v2.mainCharacter.totalKills
	end

	return v1
end

---Parse a single set of rankings from `state`
---@param decoder BitDecoder
---@param state ParseState
---@param lookup table<number, string>
---@return ProviderProfileV2Rankings
local function parseRankings(decoder, state, lookup)
	---@type ProviderProfileV2Rankings
	local result = {}
	result.spec = decoder.decodeString(state, lookup)
	result.progressKilled = decoder.decodeInteger(state, 1)
	result.progressPossible = decoder.decodeInteger(state, 1)
	result.bestAverage = decoder.decodePercentileFixed(state)
	result.allStarRank = decoder.decodeInteger(state, 3)
	result.allStarPoints = decoder.decodeInteger(state, 2)

	local encounterCount = decoder.decodeInteger(state, 1)
	result.encountersById = {}
	for i = 1, encounterCount do
		local id = decoder.decodeInteger(state, 4)
		local kills = decoder.decodeInteger(state, 2)
		local best = decoder.decodeInteger(state, 1)
		local isHidden = decoder.decodeBoolean(state)

		result.encountersById[id] = { kills = kills, best = best, isHidden = isHidden }
	end

	return result
end

---Parse a binary-encoded data string into a provider profile
---@param decoder BitDecoder
---@param content string
---@param lookup table<number, string>
---@param formatVersion number
---@return ProviderProfile|ProviderProfileV2|nil
local function parse(decoder, content, lookup, formatVersion) -- luacheck: ignore 211
	-- For backwards compatibility. The existing addon will leave this as nil
	-- so we know to use the old format. The new addon will specify this as 2.
	formatVersion = formatVersion or 1
	if formatVersion > 2 then
		return nil
	end

	---@type ParseState
	local state = { content = content, position = 1 }

	local tag = decoder.decodeInteger(state, 1)
	if tag ~= V2_TAG_NUMBER then
		return nil
	end

	---@type ProviderProfileV2
	local result = {}
	result.isSubscriber = decoder.decodeBoolean(state)
	result.summary = nil
	result.sections = {}
	result.progressOnly = false
	result.mainCharacter = nil

	local sectionsCount = decoder.decodeInteger(state, 1)
	if sectionsCount == 0 then
		---@type ProviderProfileV2Summary
		local summary = {}
		summary.zoneId = decoder.decodeInteger(state, 2)
		summary.difficultyId = decoder.decodeInteger(state, 1)
		summary.sizeId = decoder.decodeInteger(state, 1)
		summary.progressKilled = decoder.decodeInteger(state, 1)
		summary.progressPossible = decoder.decodeInteger(state, 1)
		summary.totalKills = decoder.decodeInteger(state, 2)

		result.summary = summary
	else
		for i = 1, sectionsCount do
			---@type ProviderProfileV2Section
			local section = {}
			section.zoneId = decoder.decodeInteger(state, 2)
			section.difficultyId = decoder.decodeInteger(state, 1)
			section.sizeId = decoder.decodeInteger(state, 1)
			section.partitionId = decoder.decodeInteger(state, 1) - 128
			section.totalKills = decoder.decodeInteger(state, 2)

			local specCount = decoder.decodeInteger(state, 1)
			section.anySpecRankings = parseRankings(decoder, state, lookup)

			section.perSpecRankings = {}
			for j = 1, specCount - 1 do
				local specRankings = parseRankings(decoder, state, lookup)
				table.insert(section.perSpecRankings, specRankings)
			end

			table.insert(result.sections, section)
		end
	end

	local hasMainCharacter = decoder.decodeBoolean(state)
	if hasMainCharacter then
		---@type ProviderProfileV2MainCharacter
		local mainCharacter = {}
		mainCharacter.zoneId = decoder.decodeInteger(state, 2)
		mainCharacter.difficultyId = decoder.decodeInteger(state, 1)
		mainCharacter.sizeId = decoder.decodeInteger(state, 1)
		mainCharacter.progressKilled = decoder.decodeInteger(state, 1)
		mainCharacter.progressPossible = decoder.decodeInteger(state, 1)
		mainCharacter.totalKills = decoder.decodeInteger(state, 2)
		mainCharacter.spec = decoder.decodeString(state, lookup)
		mainCharacter.bestAverage = decoder.decodePercentileFixed(state)

		result.mainCharacter = mainCharacter
	end

	local progressOnly = decoder.decodeBoolean(state)
	result.progressOnly = progressOnly

	if formatVersion == 1 then
		return convertToV1Format(result)
	end

	return result
end
--- the utf8 global is not available, so we polyfill utf8.offset so we can correctly find prefixes of utf8 strings
---@param str string
---@param index number
---@return number|nil
local function Utf8Offset(str, index)
	local len = #str

	if index <= 0 or index > len then
		return nil -- Out of bounds
	end

	-- Move forward to the nth character
	local count = 0
	for i = 1, len do
		local byte = string.byte(str, i)
		local isContinuationByte = byte >= 128 and byte < 192
		if not isContinuationByte then
			count = count + 1
			if count == index then
				return i
			end
		end
	end

	return nil -- If the nth character is not found
end

---@param table table<string, string> raw data table with character name prefixes as keys
---@param length number the number of complete characters to include in the prefix
---@return fun(characterName: string):string|nil getChunk function to retrieve a character chunk by prefix using a complete character name
local function getChunkLookup(table, length)
	return function(characterName)
		local startOfNextCharacter = Utf8Offset(characterName, length + 1)

		local prefix
		if startOfNextCharacter == nil then
			prefix = characterName
		else
			prefix = string.sub(characterName, 1, startOfNextCharacter - 1)
		end

		return table[prefix]
	end
end

local lookup = {'Mage-Arcane','Unknown-Unknown','Paladin-Retribution','DeathKnight-Blood','Hunter-BeastMastery','Hunter-Marksmanship','Paladin-Protection','Mage-Frost','Priest-Holy','Warrior-Arms','DeathKnight-Unholy','Shaman-Restoration','Rogue-Subtlety','Paladin-Holy','Warlock-Demonology','Warlock-Affliction','Druid-Guardian','Evoker-Devastation','Druid-Balance','Rogue-Assassination','Priest-Shadow','Evoker-Preservation','Shaman-Elemental','Warlock-Destruction','Priest-Discipline','Rogue-Outlaw','Warrior-Protection','DeathKnight-Frost','Druid-Restoration',}
local provider = {region='US',realm='Azuremyst',name='US',type='weekly',zone=53,date='2026-10-06',data={Aa='Aaravos:BAAANQAECgYIBgAAAA==.Aatrøx:BAAANQAECgMIBgAAAA==.',
Ac='Accretion:BAAANQADCgcIBwAAAA==.',
Ad='Addath:BAAANQADCgYIBgAAAA==.Adura:BAAANQADCgEIAQAAAA==.',
Ae='Aeirith:BAABNQAECoEdAAIBAAgKFxfSkgA+AgABAAgKFxfSkgA+AgAAAA==.',
Ai='Ailsà:BAAANQADCgIJAgABNQAECgUICgACAAAAAA==.Airius:BAAANQAECgEIAQAAAA==.',
Al='Alannon:BAAANQADCgQIBAAAAA==.Alayana:BAAANQAECgEIAwAAAA==.Aldyah:BAAANQADCgMIAwAAAA==.',
Am='Amalthia:BAAANQAECgUIBQAAAA==.Amarasu:BAAANQAECgUICgAAAA==.Amarlly:BAAANQAECgUICAAAAA==.',
An='Ancelina:BAAANQAECgQIBQAAAA==.Anderton:BAABNQAECoEgAAIDAAcKSBCTpQCdAQADAAcKSBCTpQCdAQAAAA==.Andilocks:BAAANQADCgcIGwAAAA==.Anditracks:BAAANQADCggIFwAAAA==.Andraenei:BAAANQAECgUIBQAAAA==.Andrela:BAAANQAECgEIAQAAAA==.Aneira:BAAANQAECgUICgAAAA==.',
Ap='Applefritter:BAAANQADCggIDQABNQAECgQIDQACAAAAAA==.',
Aq='Aquarius:BAAANQADCgcIBwAAAA==.',
Ar='Araest:BAAANQADCgUIBQAAAA==.Araga:BAABNQAECoEnAAIEAAkKKyJECABsAwAEAAkKKyJECABsAwAAAA==.Archmedies:BAAANQADCgEIAQAAAA==.Archérhiro:BAACNQAFFIENAAMFAAUK4xpHBgDEAQAFAAUK4xpHBgDEAQAGAAEKhgLeIgA1AAA1AAQKgTEAAwUACQquI8AOAFgDAAUACQquI8AOAFgDAAYABQp9E648AD0BAAAA.Arillann:BAABNQAECoEZAAIHAAgK7CBpCgDVAgAHAAgK7CBpCgDVAgAAAA==.Arin:BAAANQAECgQIBgABNQAECgcIEgACAAAAAA==.Arms:BAAANQADCgUIBQABNQAECgcIEAACAAAAAA==.Arrook:BAAANQADCgYICgAAAA==.Artdemsamis:BAAANQAECggIEQAAAA==.',
As='Asclëpius:BAAANQADCgIIAgABNQADCgYJBgACAAAAAA==.Ashylock:BAAANQAECggIDgABNQAFFAQICAABAK4MAA==.Ashymage:BAACNQAFFIEIAAIBAAQKrgypIwApAQABAAQKrgypIwApAQA1AAQKgTAAAwEACQqCHng7AAIDAAEACQqCHng7AAIDAAgAAQrTClM/ADYAAAAA.Askevar:BAAANQAECgUIDQAAAA==.Asriél:BAAANQAECgcIEwAAAA==.Assoul:BAAANQABCgIIBAAAAA==.Astrea:BAAANQABCggIDAAAAA==.Astridia:BAAANQAECgIIAwABNQAFFAQICgAJABEQAA==.Asuya:BAAANQAECgEJAQAAAA==.',
At='Atlassian:BAAANQAECgIJAgAAAA==.Atreus:BAAANQAECgUICQAAAA==.',
Az='Azaleah:BAABNQAECoEgAAIDAAgKcBFjfAABAgADAAgKcBFjfAABAgAAAA==.Azlan:BAAANQADCgQIBAAAAA==.Azraesha:BAAANQAECgYIDAAAAA==.Azureflamez:BAAANQADCgYJBgAAAA==.',
Ba='Backy:BAAANQADCgIIAgAAAA==.',
Be='Beareold:BAAANQAECgEIAQAAAA==.Beary:BAAANQAECgIIAwAAAA==.Beefcakes:BAAANQADCgYIBgAAAA==.Benimaru:BAAANQADCgQJBAAAAA==.',
Bi='Bigblunt:BAAANQAECgQICQAAAA==.Bigmon:BAABNQAECoE5AAIKAAkK/yCiGABLAwAKAAkK/yCiGABLAwAAAA==.',
Bj='Bjornulfr:BAAANQADCgIIAgAAAA==.',
Bl='Blackadder:BAAANQAECgQIBQAAAA==.Blackstaff:BAAANQADCggJCgAAAA==.Blessthefall:BAAANQAECggIBAAAAA==.Bloodygrundl:BAABNQAECoEZAAIEAAgKaR/OGgDAAgAEAAgKaR/OGgDAAgAAAA==.Bluestorm:BAAANQAECgUICQAAAA==.',
Bo='Bonegrinda:BAABNQAECoEdAAILAAcKayCHKgBrAgALAAcKayCHKgBrAgAAAA==.Borledish:BAAANQADCgQIBAABNQAFFAMIAwACAAAAAA==.',
Br='Branwynn:BAAANQADCgYIBwAAAA==.Bringg:BAAANQADCgYICgAAAA==.',
Ca='Caidinn:BAAANQADCgUIBQAAAA==.Calissancia:BAAANQAECgEIAQAAAA==.Calliaa:BAAANQADCgYIBgAAAA==.Callmemommy:BAAANQAECgEIAQAAAA==.Catovia:BAAANQAECgMIAwAAAA==.',
Ce='Ceallachan:BAAANQAECgUIBgAAAA==.Ceri:BAAANQAECggIAQAAAA==.Ceska:BAAANQADCgIIAgAAAA==.',
Ch='Channingtotm:BAACNQAFFIERAAIMAAUKqx6ABgDYAQAMAAUKqx6ABgDYAQA1AAQKgSEAAgwACQq6JIMJAGEDAAwACQq6JIMJAGEDAAAA.Chantix:BAAANQADCgMIAwAAAA==.Chaosshadow:BAAANQAECgYIDwAAAA==.Chaosti:BAAANQAECgYIEAAAAA==.Cheekymonkey:BAABNQAECoEdAAIBAAgK2wldzwDCAQABAAgK2wldzwDCAQAAAA==.Chrispbacon:BAAANQADCgQIBQAAAA==.Christy:BAAANQADCggICgAAAA==.Chueyé:BAAANQADCgUIBQABNQAECgkJIgANAModAA==.Chune:BAAANQADCgEIAQAAAA==.Churros:BAAANQAECgEIAQABNQAECgQIDQACAAAAAA==.',
Co='Cobiepaladin:BAAANQAECgYIBgAAAA==.Coconuts:BAAANQAECgEIAQAAAA==.Corafel:BAAANQAECgIIAgAAAA==.Cordialkylie:BAAANQAECgMIAwAAAA==.',
Cr='Cross:BAABNQAECoEfAAIOAAUKkh91ZQDCAQAOAAUKkh91ZQDCAQAAAA==.Crosslock:BAAANQADCgcICgAAAA==.',
Cu='Cuack:BAAANQADCgUICAAAAA==.',
Cy='Cynnari:BAAANQAECgQIDQAAAA==.',
Da='Dagnabit:BAAANQADCggIFAAAAA==.Daisydeath:BAAANQADCgEIAQAAAA==.Dalaris:BAAANQAECgYICwAAAA==.Darkpriestes:BAAANQADCgQIBAAAAA==.Darling:BAAANQADCgIIAgAAAA==.Darrosh:BAAANQAECgUIDwAAAA==.Dartian:BAAANQAECgMJAwABNQAECgQIDAACAAAAAA==.',
De='Deathmare:BAAANQAECgYIDAAAAA==.Deeptroat:BAAANQADCgEIAQABNQAECgUICgACAAAAAA==.Dementia:BAAANQADCgcIBwAAAA==.Derzer:BAAANQADCgUIBgAAAA==.Design:BAABNQAECoEZAAMPAAcKDw+PjACYAQAPAAcKDw+PjACYAQAQAAEKkgneKwA1AAAAAA==.',
Di='Dibick:BAAANQABCgQIBQAAAA==.Dictaiter:BAAANQAECgQIBwAAAA==.Diltlish:BAAANQAECgMIBAAAAA==.Disconcern:BAAANQADCgIIAgAAAA==.Discontent:BAABNQAECoEdAAIKAAkKfBcxUgB4AgAKAAkKfBcxUgB4AgAAAA==.',
Dm='Dmginc:BAAANQAECgMIBAAAAA==.',
Do='Doeblin:BAAANQADCggIIQAAAA==.Domidouse:BAAANQADCgYICAAAAA==.Domivyr:BAAANQAECgMIBQAAAA==.Doubledeuces:BAAANQAECgMIAwAAAA==.Doubtz:BAAANQAFFAMIAwAAAA==.',
Dr='Drackonia:BAAANQAECgUIBQAAAA==.Dracolyte:BAAANQADCgEIAQAAAA==.Dragonflai:BAAANQAECgcIEwAAAA==.Draik:BAAANQADCgUICQAAAA==.Drakkari:BAAANQADCgcICgAAAA==.Drakkei:BAAANQAECgYIEgABNQAECggIHgARAAoWAA==.Drshortbus:BAAANQAECgUICQAAAA==.Drunkenfist:BAAANQADCgcIBwAAAA==.Drylo:BAEBNQAECoEcAAISAAgKjSORBQAlAwASAAgKjSORBQAlAwAAAA==.',
Du='Duwéndé:BAAANQADCgQIBAAAAA==.',
Ed='Edelweíss:BAAANQADCggIFwAAAA==.',
El='Elarol:BAAANQADCgYICQAAAA==.Eleonore:BAAANQAECgYIDQAAAA==.Elfie:BAAANQADCgYIBgAAAA==.Elray:BAAANQAECgMIAwAAAA==.',
Em='Emeralde:BAAANQABCgYJCgAAAA==.Emilia:BAAANQABCgQIBwAAAA==.Emptyhands:BAAANQAECgIIAgAAAA==.Emptyheals:BAAANQADCggICwAAAA==.',
Er='Erf:BAAANQADCgYICgAAAA==.Erfinden:BAAANQADCgIIBAAAAA==.',
Es='Espers:BAABNQAECoEcAAITAAgKhw7sQwC3AQATAAgKhw7sQwC3AQAAAA==.',
Et='Ethellin:BAAANQAECgYIEgAAAA==.',
Eu='Euph:BAAANQAECgEIAQAAAA==.',
Ev='Evilhearts:BAAANQADCggICAAAAA==.',
Ex='Extrabacon:BAAANQADCgUIDgAAAA==.',
Fe='Fedders:BAAANQAECgQICQABNQAECgkJJQADAJkjAA==.Feedmepizzas:BAAANQAECgEIBAAAAA==.Feildmedic:BAAANQAECgUIBgABNQAECgUIEAACAAAAAA==.Feleria:BAAANQADCgUJBQAAAA==.Felwinter:BAAANQADCgYIBgAAAA==.',
Fi='Finwé:BAAANQAECgIIAgAAAA==.Fizzysoda:BAAANQADCgcIBwAAAA==.',
Fl='Fluxarata:BAAANQAECgYIBgAAAA==.',
Fr='Fred:BAAANQAECgIIAwAAAA==.Friendly:BAABNQAECoEdAAIUAAkKESNoAwCSAwAUAAkKESNoAwCSAwAAAA==.Frightrice:BAAANQAECgQJCAAAAA==.Frioh:BAAANQADCgUICQAAAA==.',
Fu='Fullpally:BAAANQADCgYIBgAAAA==.Fuzzyhunter:BAAANQADCgQIBAAAAA==.',
['Fï']='Fïzzle:BAAANQAECgQIBQABNQAECgUICgACAAAAAA==.',
Ga='Gabel:BAAANQADCggJCAAAAA==.Gablyn:BAAANQAECgcIEwAAAA==.Gagageoff:BAAANQADCgcIEQAAAA==.Gardyson:BAAANQAECgcIEgAAAA==.Garwarmegad:BAAANQADCgcIBwAAAA==.',
Gh='Ghrash:BAAANQADCgQIBAAAAA==.',
Gl='Gloney:BAAANQADCgMIAwAAAA==.',
Go='Gojira:BAAANQABCgUIBgAAAA==.Goldenshower:BAAANQADCgUIBQAAAA==.',
Gr='Gremilien:BAABNQAECoEcAAIGAAkK5RGHHwA2AgAGAAkK5RGHHwA2AgAAAA==.Grenadeout:BAAANQAECgQIBQAAAA==.Grimaldus:BAAANQAECgEIAQAAAA==.',
Ha='Harrod:BAAANQADCgYIBgAAAA==.Hauteliotie:BAAANQAECgMIBwAAAA==.Hawkwave:BAAANQADCgIIAgABNQADCgUIBQACAAAAAA==.',
He='Hefty:BAAANQAECgUIEAAAAA==.Hellbad:BAAANQAECggICgAAAA==.Hellsspawn:BAAANQADCgUIDAAAAA==.',
Ho='Hokàge:BAABNQAECoEiAAMNAAkKyh1jGwDoAQANAAUKriFjGwDoAQAUAAQK7RjSUQApAQAAAA==.Homealone:BAAANQAECgQIBAAAAA==.Hotblood:BAAANQAECgEIAQAAAA==.',
Hu='Huey:BAAANQADCgEIAQABNQAECgcIGQAVAAIRAA==.Huntinfuzzy:BAAANQAECgcIEQAAAA==.Huugg:BAAANQABCgQIBAAAAA==.',
Hy='Hymncarrey:BAAANQAECgUIEAAAAA==.Hynkie:BAAANQAECgQICAABNQAECgkJGQAWAFMSAA==.',
Ig='Igothots:BAAANQAECgYICgABNQAECgcICgACAAAAAA==.',
In='Insanitty:BAAANQADCggJCAAAAA==.',
Ir='Irritable:BAAANQAECgYIEAAAAA==.',
Is='Isadragon:BAAANQADCgUICQABNQAECgUICgACAAAAAA==.',
Ja='Jackyll:BAAANQAECggIBwAAAA==.Jatix:BAABNQAECoEWAAIDAAkKSRWKXABYAgADAAkKSRWKXABYAgAAAA==.Jawzlyn:BAAANQADCgYIDAABNQAECgQIBQACAAAAAA==.',
Je='Jellytown:BAABNQAECoEYAAIIAAgKUB24BQCJAgAIAAgKUB24BQCJAgAAAA==.Jelorinea:BAAANQADCgYJBgAAAA==.Jessiana:BAAANQAECgEJAQAAAA==.',
Jo='Johncarlo:BAAANQAECgIIBgAAAA==.',
Jp='Jpeppers:BAAANQAECgQICQAAAA==.',
Ju='Juicylucy:BAAANQADCgQIBAAAAA==.Jundra:BAAANQADCgYICAAAAA==.Jundraa:BAAANQADCgQIBAAAAA==.Jurih:BAAANQADCggIDwAAAA==.',
['Jô']='Jôhnwick:BAABNQAECoEVAAIGAAkKhQoNKgDYAQAGAAkKhQoNKgDYAQAAAA==.',
Ka='Kaerynn:BAAANQADCgYIBgAAAA==.Kait:BAABNQAECoEYAAIFAAgKHhNnXwAuAgAFAAgKHhNnXwAuAgAAAA==.Kashmir:BAAANQAECgMIAwAAAA==.Kawdor:BAAANQAECgEIAQAAAA==.Kazola:BAAANQABCgEIAQAAAA==.',
Kh='Khota:BAAANQAECgYIBwAAAA==.',
Ko='Koldfront:BAAANQADCgYIDgAAAA==.Kollinator:BAAANQAECgQIBAAAAA==.',
Ku='Kurtina:BAABNQAECoEcAAIKAAkKpxMSbwAlAgAKAAkKpxMSbwAlAgAAAA==.',
Ky='Kyyell:BAAANQAECgIIAgAAAA==.',
La='Lafty:BAAANQAECggIDwAAAA==.Larac:BAAANQAECggICgAAAA==.',
Le='Leddy:BAAANQADCgUJCQAAAA==.Leif:BAABNQAECoEYAAISAAgKZxHcFADfAQASAAgKZxHcFADfAQAAAA==.Lemmart:BAAANQAECgYICgAAAA==.Lenik:BAAANQAECgQICwAAAA==.',
Li='Licorice:BAAANQAECgQIDQAAAA==.Lieree:BAAANQAECgYIDgAAAA==.Lilyfaye:BAAANQADCgEIAQAAAA==.Limosfire:BAAANQAECgUIBwAAAA==.',
Lo='Lockty:BAAANQAECgcICAABNQAECggIDwACAAAAAA==.Logi:BAAANQADCgUIBgAAAA==.Longtotem:BAAANQAECgMJAwAAAA==.',
Lp='Lpeppers:BAAANQADCgMIAwAAAA==.',
Lu='Lucha:BAAANQAECgIIAwAAAA==.Lucity:BAAANQAECgYICwABNQAECgkJFgADAEkVAA==.Luckyvodka:BAAANQADCgUICQAAAA==.Lunafae:BAAANQADCgYIDgAAAA==.Lunarmyst:BAAANQADCgUIBQABNQAECgEIAQACAAAAAA==.Lunà:BAAANQAECgQIBQAAAA==.',
Ly='Lystral:BAAANQAECgQIBwAAAA==.Lythalle:BAAANQADCgIIAgAAAA==.Lythwynn:BAAANQAECgUIDgAAAA==.',
Ma='Magdalena:BAAANQAECgQIBQAAAA==.Mageyboi:BAAANQADCggICAABNQAECgkJIgANAModAA==.Magickul:BAAANQAECgQIBwAAAA==.Mahano:BAAANQADCgIIAgABNQAECgcIEgACAAAAAA==.Malìficus:BAAANQADCgcIBwAAAA==.Manadâr:BAAANQAECgIIAgAAAA==.Marinas:BAAANQADCgUIDwAAAA==.Maru:BAAANQADCgYIBgAAAA==.Massili:BAAANQADCgEIAwAAAA==.Mazumaragg:BAAANQADCgQICAABNQAECgcIEgACAAAAAA==.',
Mi='Miande:BAAANQAECgUICgAAAA==.Microburst:BAABNQAECoEbAAIXAAcKGQc7kgBGAQAXAAcKGQc7kgBGAQAAAA==.Minilock:BAABNQAECoEZAAQPAAgKfQmOhgCnAQAPAAgKfQmOhgCnAQAYAAMKsQNjXQBhAAAQAAEKDAfbLAAyAAAAAA==.Missdeeds:BAAANQABCgQIBAAAAA==.Missleading:BAAANQABCgEJAQAAAA==.Missused:BAAANQABCgIIAwAAAA==.Miyagifu:BAAANQADCgMJBAABNQAECgUIEAACAAAAAA==.Mièlikki:BAAANQAECgMIBQAAAA==.',
Mo='Modelotime:BAAANQADCgMIAwAAAA==.Modsagoodtnk:BAAANQADCgEIAQABNQADCgUICwACAAAAAA==.Mongermook:BAABNQAECoEYAAIRAAcKSA9qHwBcAQARAAcKSA9qHwBcAQAAAA==.Monnkysham:BAAANQADCgYJBgAAAA==.Mooglefur:BAAANQADCgcIBwAAAA==.Moranta:BAEANQADCgYIBgAAAA==.Moshood:BAAANQADCggICwAAAA==.',
My='Myaka:BAAANQAECgIIAwAAAA==.',
['Má']='Mánáburn:BAAANQADCgQIBAAAAA==.',
['Mõ']='Mõnk:BAAANQADCgYIBgAAAA==.',
Na='Naatixa:BAABNQAECoEXAAIMAAcKTxVGYQC7AQAMAAcKTxVGYQC7AQAAAA==.Nacronor:BAAANQADCggIIAAAAA==.Naiika:BAAANQABCgQIBQAAAA==.Nasoj:BAAANQAECgQIAgAAAA==.Nauseous:BAAANQADCggJCAAAAA==.',
Ne='Nedalla:BAAANQADCgYIBgAAAA==.Nerzultash:BAAANQADCgEIAQAAAA==.Newports:BAAANQADCgcIGAAAAA==.Nexedo:BAAANQAECgEIAQAAAA==.',
Ni='Nickatnite:BAAANQAECgQIBgAAAA==.Nickelodeon:BAAANQAECgQIBAAAAA==.Nickita:BAAANQAECgIIAgAAAA==.Nightgear:BAACNQAFFIEPAAIFAAUK8xQPBwC0AQAFAAUK8xQPBwC0AQA1AAQKgUQAAgUACQoaIPQgAPYCAAUACQoaIPQgAPYCAAAA.Niteshadeth:BAAANQADCgMIAwAAAA==.Nixeava:BAAANQAECgEIAwAAAA==.',
No='Notadoctor:BAAANQAECgMIBAAAAA==.Notafurry:BAAANQADCgUICQAAAA==.',
Ny='Nysong:BAAANQADCgEIAQAAAA==.',
Oa='Oakenforge:BAABNQAECoEeAAMRAAgKCha0EQAEAgARAAgKCha0EQAEAgATAAMKawSGiwByAAAAAA==.',
Od='Ode:BAAANQAECgYIEwAAAA==.Odex:BAAANQAECgYICQAAAA==.',
On='Onlymages:BAAANQAECgQIEQAAAA==.Onos:BAAANQAECgQICwAAAA==.',
Or='Orinin:BAABNQAECoEZAAMVAAcKAhHWKgCoAQAVAAcKAhHWKgCoAQAZAAMKhgv4FwCWAAAAAA==.',
Ou='Outkíll:BAAANQAECgUIBwAAAA==.',
Pa='Pally:BAAANQAECgcIEAAAAA==.Pandarweb:BAAANQADCgUJBQAAAA==.Pathogen:BAABNQAECoEZAAILAAgK+iGxGwDJAgALAAgK+iGxGwDJAgAAAA==.',
Pe='Peachebelle:BAAANQADCgQIBAAAAA==.Peaches:BAAANQADCgUIBQAAAA==.Persephoni:BAAANQAECgQIDQAAAA==.Perve:BAAANQAECgUJCQABNQAECgcIEwACAAAAAA==.',
Pf='Pfchen:BAAANQADCgYIBwAAAA==.',
Pi='Pippy:BAAANQAECgEIAQAAAA==.',
Pl='Plaguestrip:BAAANQADCgIIAgAAAA==.Plinkerbell:BAAANQAECgEIAwAAAA==.',
Po='Poppit:BAAANQADCgYIBgAAAA==.Porimma:BAAANQADCgMIAwAAAA==.',
Pr='Prom:BAAANQADCgMIAwAAAA==.Promethèus:BAABNQAECoEbAAIBAAgK8BqjdwB4AgABAAgK8BqjdwB4AgAAAA==.',
Pu='Puffypuff:BAAANQADCggICAAAAA==.',
Qo='Qoheleth:BAAANQAECgYICwAAAA==.',
Qu='Quanjo:BAAANQADCgUIBQAAAA==.Queedle:BAABNQAECoEXAAIaAAgKZAkHCwCiAQAaAAgKZAkHCwCiAQAAAA==.',
Qw='Qwacker:BAAANQADCgUIDgAAAA==.',
Ra='Ragalstan:BAAANQABCggJDAAAAA==.Rainlette:BAAANQAECgQIBQAAAA==.Rainsvoker:BAACNQAFFIEJAAISAAUKFg91BABzAQASAAUKFg91BABzAQA1AAQKgU4AAhIACQrNINoDAFUDABIACQrNINoDAFUDAAAA.Ramike:BAABNQAECoEeAAIbAAcKBxsvDwALAgAbAAcKBxsvDwALAgAAAA==.Randal:BAAANQABCgIIAgAAAA==.',
Re='Reaveldahar:BAAANQADCgUJCQAAAA==.Recovery:BAAANQAECgEIAQAAAA==.Reddan:BAAANQAECgQIDgAAAA==.Rei:BAAANQADCgUIBQAAAA==.Restodrood:BAAANQADCgUJAwABNQAECgkJIgANAModAA==.Retman:BAAANQABCgIIAgAAAA==.Revy:BAAANQAECgQJBAAAAA==.',
Ri='Rinji:BAAANQADCggIDgAAAA==.Rit:BAAANQAECgYIDAAAAA==.Ritzon:BAABNQAECoEYAAIKAAgKKxosWABmAgAKAAgKKxosWABmAgAAAA==.',
Ro='Rosara:BAAANQADCggICAAAAA==.',
Rr='Rrook:BAAANQADCgQIBgAAAA==.',
Ry='Ryanrainolds:BAAANQADCgQIBAABNQAECgUIEAACAAAAAA==.Rykken:BAAANQAECgEIAQABNQAECgIIAgACAAAAAA==.',
['Rà']='Ràncore:BAAANQADCgEIAQAAAA==.',
Sa='Santacloz:BAAANQADCgQIBAAAAA==.',
Sc='Scubasteve:BAAANQAECgEIAwAAAA==.',
Se='Segan:BAAANQADCgcIBwAAAA==.Sell:BAAANQADCgMIAwAAAA==.Sellex:BAAANQADCggIHwAAAA==.',
Sh='Shamalaya:BAAANQADCgUIBgAAAA==.Shamburgler:BAAANQAECgIIAwAAAA==.Shan:BAAANQAECgcIDwAAAA==.Shaxx:BAABNQAECoEZAAIDAAkKbBwUQACwAgADAAkKbBwUQACwAgAAAA==.Sherrilu:BAAANQADCgIIAgAAAA==.Shiera:BAAANQADCggIDgAAAA==.Shmoove:BAAANQADCgYIBgABNQAECgIIAwACAAAAAA==.',
Si='Sieya:BAAANQADCggIFQAAAA==.Sinarria:BAAANQADCgUICAAAAA==.Sithra:BAAANQADCgQIBAAAAA==.',
Sk='Skitzop:BAAANQAECgQIBAAAAA==.Skullace:BAAANQAECgQIBwAAAA==.Skullhead:BAAANQABCggIIgAAAA==.Skylette:BAAANQADCggJDQAAAA==.',
Sl='Slash:BAAANQADCgEIAQAAAA==.Slilith:BAAANQABCgIIAgAAAA==.',
Sn='Snakeblitzen:BAAANQADCgQIBAAAAA==.Snakesix:BAAANQADCgYIBwAAAA==.Snarf:BAAANQADCgUICQABNQAECgcIEgACAAAAAA==.',
So='Soothingdusk:BAAANQAECgEIAQAAAA==.',
Sp='Sparkplugg:BAAANQADCgQIBAAAAA==.Sparthos:BAAANQAECgUIEgAAAA==.Spideyrogue:BAAANQAECgEIAQAAAA==.Springbuck:BAAANQABCgIJAgAAAA==.',
Sr='Srfreaky:BAAANQADCggIGgAAAA==.',
St='Stabatha:BAAANQAECgEIAQAAAA==.Stepbrogon:BAAANQADCgYICAAAAA==.Sterlìng:BAABNQAECoEcAAIcAAcKvgj1SQBJAQAcAAcKvgj1SQBJAQAAAA==.Stocklock:BAAANQADCggIDwAAAA==.Stormblessed:BAAANQADCgQJBAAAAA==.Stowned:BAAANQAECgEIAQAAAA==.Stumpyborg:BAAANQAECgEIAQABNQAECgUIEAACAAAAAA==.',
Su='Sune:BAAANQADCgUICQAAAA==.Suzuya:BAAANQABCggICAAAAA==.',
Sy='Sympåthy:BAAANQAECgEIAQAAAA==.',
Ta='Takoyaki:BAAANQADCgMIAwAAAA==.Tapartos:BAAANQADCgIIAgABNQAECgcIEgACAAAAAA==.Tatari:BAAANQADCgYJCgABNQAECgQICAACAAAAAA==.Tavenon:BAAANQAECgEIAQAAAA==.',
Te='Telandril:BAABNQAECoEYAAIdAAgKWhDeJgC6AQAdAAgKWhDeJgC6AQAAAA==.Tellanna:BAAANQAECgYIDwAAAA==.Tensuken:BAAANQAECgUIDQAAAA==.Teriyaki:BAAANQADCgMIAwAAAA==.Testarossaa:BAAANQAECgUICAAAAA==.',
Th='That:BAAANQADCgYIBgAAAA==.Thauríel:BAAANQAECgQJBAAAAA==.Thebran:BAAANQADCggJEAAAAA==.Thejuiciest:BAAANQAECgYIBgAAAA==.Theunclepaul:BAAANQAECgUICgAAAA==.',
Ti='Tiarl:BAABNQAECoErAAIJAAgKqxqbNQBwAgAJAAgKqxqbNQBwAgAAAA==.Tinydots:BAAANQAECgUIDAAAAA==.',
To='Tom:BAAANQADCgMIBAAAAA==.Tomoyá:BAAANQADCgYIBgAAAA==.Toniichopper:BAAANQAECgEJAQAAAA==.Tonn:BAAANQADCgUIDgAAAA==.Toosxyfohair:BAAANQADCgYIGwAAAA==.Torhal:BAAANQADCgIIAgAAAA==.',
Tr='Trimble:BAAANQABCggIBgAAAA==.',
Tt='Tt:BAAANQAFFAMIAwAAAA==.',
Tu='Tuv:BAAANQAECgQIBAAAAA==.',
Tw='Twentytwo:BAAANQADCgIIAgAAAA==.Twylo:BAEANQAECggICAABNQAECggIHAASAI0jAA==.',
Ty='Tyiedis:BAAANQADCgYJBwAAAA==.Tyrànda:BAAANQADCgUIDAAAAA==.',
Ul='Ulanhi:BAAANQAECgQIBgAAAA==.Uling:BAAANQADCgEIAQAAAA==.',
Un='Undeadjelly:BAAANQAECgUIBwAAAA==.Unfriendly:BAAANQADCggIDAAAAA==.',
Va='Vaelora:BAAANQADCggICAAAAA==.Valakk:BAAANQAECgMIBAAAAA==.Valsitril:BAAANQAECgUIDgABNQAECgYICwACAAAAAA==.Vanara:BAAANQABCggICwAAAA==.Varelyna:BAAANQADCgYIBgABNQAECgYICwACAAAAAA==.',
Ve='Velsetin:BAAANQADCgQIBAABNQAECgcICwACAAAAAA==.Venum:BAAANQAECgEIAQAAAA==.Vexian:BAAANQADCgcIGQABNQAECgcIGwAVANkZAA==.',
Vi='Vicas:BAAANQAECgIIAgAAAA==.Vipbull:BAAANQADCgYIBwAAAA==.Vixena:BAAANQADCgUIBgAAAA==.',
Vl='Vladdok:BAAANQADCgUIBQAAAA==.',
Vo='Voidzzmid:BAAANQADCgIIAgAAAA==.',
Wa='Warded:BAAANQADCggIDwAAAA==.',
We='Wesjenks:BAAANQAECgUICAAAAA==.',
Wh='Whisperlia:BAAANQAECgIIAgAAAA==.Whisperwindd:BAAANQAECgIIAgAAAA==.White:BAAANQADCgUIBgAAAA==.Whitetoothe:BAAANQAECgEIAQAAAA==.',
Wi='Wilco:BAAANQAECggIBgAAAA==.',
Wo='Workin:BAAANQADCgIIAgABNQAECgQICAACAAAAAA==.',
Xa='Xandina:BAAANQADCgQICQAAAA==.Xanndor:BAAANQABCggICAAAAA==.',
Xi='Xiuhtecuhtli:BAAANQADCgUIBgAAAA==.',
['Xâ']='Xâxâs:BAAANQADCggIFAABNQAECgEIAQACAAAAAA==.',
Ya='Yaerin:BAABNQAECoEcAAMJAAgKUCLaFwAAAwAJAAgKUCLaFwAAAwAZAAMK0Q4QGACVAAAAAA==.Yahman:BAAANQAECgQIBAABNQAECgkJJQABAGUlAA==.Yaoi:BAABNQAECoEgAAMMAAgKSAjVggBXAQAMAAgKSAjVggBXAQAXAAYKmgOctQD4AAAAAA==.',
Ye='Yevanendra:BAAANQADCgYICgAAAA==.',
Yo='Yokof:BAAANQAECgUIBQAAAA==.',
Yu='Yungfungi:BAAANQADCgcIDgAAAA==.Yuukon:BAABNQAECoEdAAIcAAgKbQ/VNADLAQAcAAgKbQ/VNADLAQAAAA==.',
Za='Zackman:BAAANQADCgYICQAAAA==.Zad:BAAANQAECgQIAwABNQAFFAQICQAcAAMXAA==.Zadira:BAACNQAFFIEJAAIcAAQKAxdPBgBRAQAcAAQKAxdPBgBRAQA1AAQKgSoAAxwACQqHHuAWALACABwACQr+HeAWALACAAQAAwraGUR+ANoAAAAA.Zadirasham:BAAANQAECgcIDAABNQAFFAQICQAcAAMXAA==.',
Ze='Zeeze:BAAANQADCgcIBwAAAA==.Zephrylia:BAAANQADCgYIFQAAAA==.',
Zu='Zuriel:BAAANQAECgQICQAAAA==.',
Zy='Zyku:BAAANQADCgEIAQAAAA==.Zylphia:BAAANQAECgYIBgAAAA==.',
['Àm']='Àmagezing:BAAANQAECgIIAgABNQAECgkJHQAHAKwhAA==.',
['Èx']='Èxcision:BAAANQADCgUIBQAAAA==.',
['Ös']='Östara:BAAANQAECgQICAAAAA==.',
},}
provider.parse = parse

local rawData = provider.data
provider.data = {}
provider.getChunk = getChunkLookup(rawData, 2)

provider.splitId = 0
provider.splitCount = 1
provider.splitType = 'none'

setmetatable(provider.data, {
	__index = function(table, key)
		provider.getChunk(key)
	end,
})

if _G["ArchonTooltip"] and ArchonTooltip.AddProviderV2 then
	ArchonTooltip.AddProviderV2(lookup, provider)
end
