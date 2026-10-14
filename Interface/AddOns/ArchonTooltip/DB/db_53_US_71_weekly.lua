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

local lookup = {'Mage-Arcane','Shaman-Restoration','Shaman-Elemental','Warlock-Affliction','Mage-Frost','Warlock-Demonology','Unknown-Unknown','Priest-Holy','Druid-Guardian','DeathKnight-Frost','DeathKnight-Blood','Warrior-Arms','Druid-Balance','Druid-Restoration','Hunter-BeastMastery','Rogue-Assassination','Paladin-Retribution','Monk-Mistweaver','Evoker-Devastation','DemonHunter-Havoc','Monk-Windwalker','Warlock-Destruction','Warrior-Protection','Druid-Feral','Paladin-Holy','Hunter-Marksmanship','Shaman-Enhancement','Paladin-Protection','Rogue-Outlaw','DemonHunter-Devourer','Evoker-Preservation','Evoker-Augmentation','Mage-Fire','DeathKnight-Unholy',}
local provider = {region='US',realm='Draenor',name='US',type='weekly',zone=53,date='2026-10-13',data={Ab='Abhire:BAAANQAECgQIBQABNQAECgkJIAABAN4WAA==.',
Ad='Advisor:BAABNQAECn8oAAMCAAkKDSMnCQB2AwACAAkKDSMnCQB2AwADAAEKMw/FJwE9AAAAAA==.',
Ae='Aería:BAABNQAECn8gAAICAAkKIyA/HAD7AgACAAkKIyA/HAD7AgAAAA==.',
Ak='Akarm:BAAANQAECgMIAQAAAA==.',
Al='Alyà:BAAANQAECgUICwABNQAECgkJHwAEAGoMAA==.',
Am='Amalia:BAAANQABCgIJAgAAAA==.Amandakk:BAAANQAECgEIAQAAAA==.',
An='Angelicuss:BAAANQADCgcICAABNQAECggIIwAFAD8kAA==.',
Ap='Aparajita:BAABNQAECn8pAAIGAAkKux6kIAD/AgAGAAkKux6kIAD/AgABNQAECgQIBQAHAAAAAA==.Aphrodite:BAABNQAECn8eAAIIAAkKQRtTJADYAgAIAAkKQRtTJADYAgAAAA==.',
Ar='Arianda:BAABNQAECn8nAAIJAAkKXyJsAwB+AwAJAAkKXyJsAwB+AwAAAA==.Aristoleh:BAAANQAECgQIBgABNQAECgkJJwADAAwaAA==.Armagedonn:BAAANQADCgQIBAAAAA==.Arolder:BAABNQAECn8oAAMKAAkKVCJ0EAAJAwAKAAkKnCB0EAAJAwALAAcKiSNrGgDZAgAAAA==.Artemis:BAAANQABCgYJBgABNQAECgkJHgAIAEEbAA==.',
As='Astayuno:BAAANQAECgIIAwAAAA==.',
At='Atoadaso:BAABNQAECn8WAAIMAAcKtBpAhAANAgAMAAcKtBpAhAANAgAAAA==.',
Av='Avoidit:BAAANQADCgEIAQABNQADCggILAAHAAAAAA==.Avoidme:BAAANQADCgEIAQAAAA==.',
Az='Azazél:BAABNQAECn8fAAIEAAkKagyuBwAcAgAEAAkKagyuBwAcAgAAAA==.Azcowboy:BAAANQADCgEIAQAAAA==.Aznå:BAAANQADCgEIAQAAAA==.Azrok:BAAANQABCgIIAgAAAA==.Azurjinn:BAAANQADCgEIAQAAAA==.',
Ba='Balacheck:BAAANQAECgIIAwAAAA==.Bankus:BAAANQADCgUIBQAAAA==.Barakka:BAAANQABCgIIAgAAAA==.',
Bb='Bbite:BAABNQAECn8YAAMNAAUKcRjDWQBpAQANAAUKcRjDWQBpAQAOAAEKYgd9dgAuAAAAAA==.',
Bi='Bigbadwoof:BAAANQADCgYIDgAAAA==.Bipbipbup:BAAANQADCgYIDQAAAA==.',
Bj='Björn:BAAANQADCggIEAAAAA==.',
Bl='Blasphemar:BAAANQADCgUIBQAAAA==.Blinkz:BAAANQAECgEJAQAAAA==.',
Bo='Bogarash:BAAANQABCgIIAgAAAA==.Boombástic:BAABNQAECn8lAAMOAAgKARKVJgDqAQAOAAgKARKVJgDqAQANAAUKUQi+eQDfAAAAAA==.Boomco:BAABNQAECn8nAAIPAAgKjQqqjADtAQAPAAgKjQqqjADtAQAAAA==.Bordinn:BAAANQADCgIIAgAAAA==.',
Br='Bravillius:BAAANQADCggIDQAAAA==.Breeti:BAAANQAECgIIAgAAAA==.Broin:BAAANQAECgEIAQABNQAECgEIAQAHAAAAAA==.Bryda:BAAANQAECgUIBgAAAA==.',
Bu='Bubblecreep:BAAANQADCgQIBQABNQAECgYICQAHAAAAAA==.Burblingbee:BAAANQAECgQIBAAAAA==.Burtangus:BAAANQAECgUICAAAAA==.Butch:BAAANQAECgYIBwAAAA==.Butteskull:BAAANQAECgEIAQAAAA==.',
Bw='Bwucewee:BAAANQADCgYJFQAAAA==.',
Ca='Cajbo:BAABNQAECn8YAAIQAAcK8hmYLgAlAgAQAAcK8hmYLgAlAgAAAA==.Calyssa:BAABNQAECn8kAAIRAAkKGhldTwCjAgARAAkKGhldTwCjAgAAAA==.Cancarn:BAAANQABCgYICwAAAA==.Capmkrunch:BAAANQADCgUIBQABNQADCgYICAAHAAAAAA==.Capybara:BAAANQAECggIEAABNQAFFAUICwANANkYAA==.Cartan:BAABNQAECn8xAAISAAkK6BwUCQD4AgASAAkK6BwUCQD4AgAAAA==.Castisteus:BAAANQADCggICQAAAA==.Cathum:BAAANQAECgMIAQAAAA==.',
Ch='Charizaardx:BAACNQAFFH8MAAITAAQK5guHBwATAQATAAQK5guHBwATAQA1AAQKf0MAAhMACQpvHCgIAPYCABMACQpvHCgIAPYCAAAA.Chromeski:BAAANQAECgYIDAAAAA==.',
Cl='Clampa:BAAANQADCgYIBgAAAA==.Cletus:BAABNQAECn8YAAIMAAcKDRE4rwChAQAMAAcKDRE4rwChAQAAAA==.',
Co='Cowdeath:BAAANQADCgcIBwAAAA==.',
Cr='Creedz:BAAANQAECgIIAQAAAA==.Creepymage:BAAANQAECgYICQAAAA==.Crimsonthot:BAAANQADCgQIBAAAAA==.Crystalys:BAAANQAECgUIDgAAAA==.',
Cu='Cuto:BAAANQADCgIIAgAAAA==.Cuttie:BAAANQADCgYIEAAAAA==.',
Cy='Cyblade:BAABNQAECn8VAAIUAAcKdBW+PwC6AQAUAAcKdBW+PwC6AQAAAA==.',
Da='Dalna:BAABNQAECn8XAAMSAAcKtw18JABVAQASAAcKtw18JABVAQAVAAUK7wcJTADDAAAAAA==.Darkderek:BAAANQADCgUIDAAAAA==.Darklürker:BAAANQAECgUICgAAAA==.Darksaber:BAAANQADCggIEgAAAA==.Darkwi:BAABNQAECn8rAAMWAAkK1hDgHgB2AQAGAAcKSw9sjgC9AQAWAAYKqRHgHgB2AQAAAA==.Dasthodan:BAAANQADCggIDgABNQAECgYIDAAHAAAAAA==.Dayne:BAAANQAECgQIBAAAAA==.',
Dc='Dctrpepper:BAAANQAECgEIAQAAAA==.',
De='Deadpool:BAAANQADCgUIBQABNQAECgcIFQAUAHQVAA==.Deathby:BAABNQAECn8aAAMMAAUKPgNbGQGiAAAMAAUKPgNbGQGiAAAXAAEKAADfRQAoAAAAAA==.Deathcore:BAAANQADCgcICAAAAA==.Deathtardza:BAAANQADCggIHQAAAA==.Defiant:BAAANQABCgQIBgAAAA==.Deilliann:BAABNQAECn8jAAQOAAgKHgSBQQAXAQAOAAgKHgSBQQAXAQAYAAEKAADCTAAYAAANAAEKAABcyAAXAAAAAA==.Deldawalth:BAAANQAECgYICAAAAA==.Demonica:BAAANQAECgUIEQAAAA==.Denogginizer:BAAANQADCgcIBwAAAA==.Devick:BAAANQAECgUICwAAAA==.',
Di='Dimmak:BAAANQADCggIBwAAAA==.Dinta:BAABNQAECn8mAAIRAAgKtxFYoQDZAQARAAgKtxFYoQDZAQAAAA==.',
Do='Dominoes:BAAANQAECgUICQAAAA==.Dovahhun:BAAANQADCgYIBgAAAA==.',
Dr='Drakth:BAAANQADCgYIBgAAAA==.',
Du='Dummblond:BAABNQAECn8cAAMNAAgKtggKVgB7AQANAAgKtggKVgB7AQAOAAMK6gR5YwByAAAAAA==.',
Dy='Dyonesa:BAAANQADCgMIAwAAAA==.Dysfunction:BAABNQAECn8hAAIJAAgKohgcEQBKAgAJAAgKohgcEQBKAgAAAA==.',
['Dä']='Därkstone:BAAANQADCgEJAQAAAA==.',
['Dê']='Dêlightful:BAAANQADCggICAAAAA==.',
Ea='Earthshield:BAAANQADCgEIAQABNQAECgQIBgAHAAAAAA==.',
Eg='Ego:BAABNQAECn8lAAIZAAgKTiGPHAAAAwAZAAgKTiGPHAAAAwAAAA==.',
Ei='Eiduartplis:BAAANQAECgcICwAAAA==.',
El='Ellaana:BAAANQAECgMIBQAAAA==.Ellee:BAAANQAECgQIBAAAAA==.Elotarra:BAAANQADCgYIDgAAAA==.Eluné:BAAANQADCgUJBQAAAA==.',
Em='Emordat:BAAANQAECgEIAQAAAA==.',
Ex='Exine:BAAANQADCggIFAAAAA==.',
Fa='Faethe:BAAANQADCgIIAgABNQAECggIIwAFAD8kAA==.Fananabanana:BAAANQAECgUIDgABNQAECgcIEgAHAAAAAA==.',
Fi='Figaro:BAAANQAECgUIBwABNQAECggIGgAaAGwgAA==.Finite:BAAANQADCgQIBAAAAA==.Firewater:BAABNQAECn8lAAIBAAcKHRNN2ADTAQABAAcKHRNN2ADTAQAAAA==.',
Fl='Flameheart:BAAANQAECgIIAwAAAA==.Fleathulhu:BAABNQAECn8pAAIIAAgKAhZIWAAVAgAIAAgKAhZIWAAVAgAAAA==.Flungpu:BAAANQADCggIKwABNQAECggIIQAPACcLAA==.',
Fo='Fostock:BAAANQAECgIIAwAAAA==.',
Fr='Frobenius:BAAANQAECgcICgABNQAECgkJMQASAOgcAA==.Frostmoon:BAAANQABCgcIDQAAAA==.Frozty:BAAANQADCgEIAQAAAA==.',
Ga='Galiena:BAAANQADCgQIBAAAAA==.Garwynn:BAABNQAECn8oAAIQAAgKqBEENQABAgAQAAgKqBEENQABAgAAAA==.',
Gh='Ghostkev:BAABNQAECn8hAAMPAAkKOBqgLADmAgAPAAkKOBqgLADmAgAaAAQK9weAWwCzAAAAAA==.Ghoulmaxing:BAAANQADCgEIAQABNQAECgkJMwAMAOsdAA==.',
Gl='Glaistia:BAAANQADCggIDAAAAA==.Glen:BAAANQAECgMIBQAAAA==.Glowstik:BAAANQAECgIIAgAAAA==.',
Gy='Gythaa:BAAANQAECgQIBQAAAA==.',
Ha='Habbyb:BAAANQADCgQIBAAAAA==.Habbypallie:BAAANQADCgUICgAAAA==.Halixan:BAABNQAECn8hAAIbAAkKRxy+BwD+AgAbAAkKRxy+BwD+AgAAAA==.Hankmoodie:BAAANQAECgcIDAAAAA==.Hansdragonis:BAAANQADCgIIAgAAAA==.',
He='Healze:BAAANQADCgUIBQAAAA==.Hellgrin:BAAANQAECgIIAwAAAA==.',
Ho='Holysim:BAAANQAECgIIAgAAAA==.Honir:BAABNQAECn8cAAIcAAgKlB9yDQDBAgAcAAgKlB9yDQDBAgAAAA==.',
['Hâ']='Hâvoc:BAAANQADCgYIEQAAAA==.',
['Hü']='Hünter:BAAANQAECgEJAQAAAA==.',
Ih='Ihlyria:BAAANQADCgYICAABNQAECggIIwAFAD8kAA==.',
Il='Illidaguerre:BAAANQABCgIJAgAAAA==.',
Im='Imonster:BAABNQAECn8aAAMWAAgK0weDNQDrAAAGAAcKjQiNvABPAQAWAAYKVAODNQDrAAAAAA==.Imooforu:BAAANQADCgUJBgABNQADCgUIDAAHAAAAAA==.',
Ir='Irevoke:BAAANQADCgQIBAAAAA==.Iridia:BAAANQADCgIIAgAAAA==.',
Is='Islet:BAAANQADCgQICAAAAA==.',
Ja='Jaegas:BAAANQAECgYICQAAAA==.Jaen:BAAANQADCggIDgABNQAECgcIIQAIADASAA==.Jamus:BAAANQAECgQIBgAAAA==.Jarvy:BAAANQAECgMJAwAAAA==.',
Ji='Jiangshi:BAAANQADCgQIBAAAAA==.',
Jo='Johnzandalar:BAAANQADCgcIEgAAAA==.',
Ju='Justpwnedu:BAAANQAECggICgAAAA==.',
Ka='Kaazel:BAABNQAECn8hAAIPAAgKJwuakQDiAQAPAAgKJwuakQDiAQAAAA==.Kaladiin:BAAANQAECgUIDgAAAA==.Kallias:BAABNQAECn8iAAIZAAgKaiK5GAAVAwAZAAgKaiK5GAAVAwAAAA==.Kandistars:BAABNQAECn8gAAINAAcKsBJQSwCzAQANAAcKsBJQSwCzAQAAAA==.Karite:BAABNQAECn8lAAIdAAgKix5bBQCZAgAdAAgKix5bBQCZAgAAAA==.Karlov:BAAANQADCgYIDAAAAA==.Kaymyn:BAABNQAECn8fAAIFAAgKsxT/CwD6AQAFAAgKsxT/CwD6AQAAAA==.Kazar:BAAANQADCgUICgAAAA==.Kazenoth:BAAANQADCgUIBQAAAA==.',
Ke='Kehjistan:BAAANQAECgYICQAAAA==.Kennychaoss:BAABNQAECn8gAAICAAgKsxgITQAsAgACAAgKsxgITQAsAgAAAA==.Kennykaoss:BAAANQADCgUIBQAAAA==.',
Ki='Kille:BAAANQAECgQIBQAAAA==.Killyoualot:BAAANQAECgQIBAAAAA==.',
Ko='Koland:BAAANQADCgcIEQAAAA==.Kosseluna:BAABNQAECn8XAAINAAcK1QW1ZwApAQANAAcK1QW1ZwApAQAAAA==.Kostazu:BAABNQAECn8jAAIDAAgKbgw0dwC4AQADAAgKbgw0dwC4AQAAAA==.',
La='Laity:BAAANQAECgUICgAAAA==.Lazariir:BAAANQAECgMIAwAAAA==.Lazkal:BAAANQAECgQIBgAAAA==.',
Le='Lebesgue:BAABNQAECn8aAAICAAgKLRokPQBoAgACAAgKLRokPQBoAgABNQAECgkJMQASAOgcAA==.Lebigmu:BAAANQAECgUIDwAAAA==.Leelee:BAAANQAECgUIBgAAAA==.',
Li='Lilbones:BAAANQADCgUIBQABNQAECgkJMwAMAOsdAA==.Lisettar:BAAANQAECgcICgAAAA==.',
Lo='Lockncreep:BAAANQADCgUIDAABNQAECgYICQAHAAAAAA==.Lolwut:BAAANQABCgUICAAAAA==.',
Lu='Luminary:BAAANQAECgYICgABNQAECgcIBQAHAAAAAA==.Lunariss:BAAANQADCgYICQABNQADCgcIDQAHAAAAAA==.Luralia:BAAANQAECgUICAAAAA==.',
Ly='Lycanbyte:BAAANQADCggILQAAAA==.Lylith:BAABNQAECn8kAAIeAAgKhhWhJwAEAgAeAAgKhhWhJwAEAgAAAA==.',
Ma='Macryver:BAAANQADCgIIAgAAAA==.Magdalena:BAAANQAECgUIDQAAAA==.Magegrumpy:BAAANQADCgIIAgAAAA==.Magikos:BAAANQADCgUIBQAAAA==.Magmaface:BAAANQAECgUIBQAAAA==.Magnólia:BAABNQAECn8hAAICAAcKHyX1JQDLAgACAAcKHyX1JQDLAgABNQAECgkJKgAZAAcfAA==.Mahan:BAAANQADCgQIBAAAAA==.Mahito:BAAANQADCgIIAgAAAA==.Mangomondy:BAAANQADCgYIBgAAAA==.Marathon:BAAANQAECgUICwAAAA==.Maribelle:BAAANQAECgEIAQABNQAECggIIwAFAD8kAA==.Masha:BAAANQADCgIIAgAAAA==.Maximander:BAAANQADCgIIAgAAAA==.',
Me='Melomel:BAAANQAECgIIAwAAAA==.Melonsquezer:BAABNQAECn8hAAIcAAgK5x48EQCKAgAcAAgK5x48EQCKAgAAAA==.Menmei:BAAANQAECgIIAwAAAA==.Meow:BAAANQAECgQIBgAAAA==.Merphia:BAAANQADCgEIAQAAAA==.Meygen:BAAANQAECgYIEgAAAA==.',
Mi='Milkman:BAAANQABCgEIAQABNQAECggIFAARAOYZAA==.Minien:BAABNQAECn8cAAIbAAgKtRbmEABZAgAbAAgKtRbmEABZAgAAAA==.Minko:BAAANQABCgQIBAAAAA==.Minore:BAAANQAECgcICwAAAA==.',
Mo='Moa:BAAANQAECgYIEwABNQAECgkJHwAEAGoMAA==.Moneybadger:BAAANQABCgIIAgAAAA==.Moonshot:BAABNQAECn8jAAIaAAgKzhI1KgD3AQAaAAgKzhI1KgD3AQAAAA==.Moortz:BAAANQAECgIIAgABNQAECgkJIAAaABAhAA==.Morillic:BAABNQAECn8eAAQEAAgKeRqIBACQAgAEAAgKeRqIBACQAgAWAAMKlxP4PwDBAAAGAAMKJRFYDQGqAAAAAA==.Mortegurn:BAAANQABCgYICwAAAA==.',
Ms='Mstrcrowly:BAAANQAECgYIBgAAAA==.',
My='Myros:BAABNQAECn8hAAMFAAgKLRbPHAAFAQABAAYKfxPSBgF+AQAFAAQKsxPPHAAFAQAAAA==.',
Na='Nadiaa:BAAANQADCggICgAAAA==.Naih:BAAANQADCgUIBQAAAA==.Nantari:BAAANQAECgEIAgABNQAECggIIQAFAC0WAA==.Narestor:BAAANQAECgQIDQABNQAECgkJKAAfAB8LAA==.Nazervis:BAACNQAFFH8RAAMTAAUKohzPAwCmAQATAAUKohzPAwCmAQAfAAEKGQF+GgAyAAA1AAQKfyUAAxMACQosJFEFADwDABMACQosJFEFADwDACAAAQrbHwIhAEsAAAAA.',
Ne='Nekopunch:BAAANQAECgUJBQAAAA==.Nelcor:BAAANQAECgUIEQAAAA==.Nemesîs:BAAANQADCggICAAAAA==.Newhealer:BAAANQAECgcIEgAAAA==.',
No='Noint:BAAANQAECgUIDgAAAA==.Nortree:BAAANQAECgIIAwAAAA==.',
Nu='Nub:BAAANQAFFAEIAQAAAA==.Nulwyrm:BAABNQAECn8gAAMTAAcK2BpYEQA9AgATAAcK2BpYEQA9AgAgAAQKGhb6EgD9AAAAAA==.',
Ny='Nymue:BAABNQAECn8gAAMDAAcKXBJ+eQCyAQADAAcKXBJ+eQCyAQAbAAEKAADKOAApAAAAAA==.Nyyrivik:BAAANQADCgYJCAAAAA==.',
Nz='Nzoth:BAAANQADCgEIAQAAAA==.',
Oc='Octapie:BAABNQAECn8lAAICAAgKqxWWWgD8AQACAAgKqxWWWgD8AQAAAA==.',
Oh='Ohitsadragon:BAAANQAECgcIDgAAAA==.',
Oo='Oograshi:BAAANQADCgQIBgAAAA==.',
Or='Oranur:BAAANQAECgQIDQAAAA==.Oreoscruunit:BAAANQADCgYICAAAAA==.Ormil:BAAANQABCgIIAgAAAA==.',
Os='Oscuridad:BAAANQAECgUICQAAAA==.',
Ow='Owl:BAABNQAECn8bAAIEAAgKtQdtDACYAQAEAAgKtQdtDACYAQAAAA==.Owlcatraz:BAACNQAFFH8GAAINAAUK3gSSEwArAQANAAUK3gSSEwArAQA1AAQKfzMAAg0ACQoeHSwSADQDAA0ACQoeHSwSADQDAAAA.',
Pa='Paendrag:BAAANQADCggIDQAAAA==.Panteragon:BAAANQAECgIIAwAAAA==.Panthean:BAAANQAECgUIDgAAAA==.Papicante:BAAANQAECgYICQAAAA==.Pashene:BAAANQAECgIIAwAAAA==.',
Pe='Peachyboy:BAAANQADCgMIAwAAAA==.Periwinkle:BAABNQAECn8iAAIIAAkKnA17ZwDkAQAIAAkKnA17ZwDkAQAAAA==.Persaud:BAABNQAECn8ZAAMWAAgKpiAZFwCzAQAGAAcK/R6bWgBEAgAWAAUK6x8ZFwCzAQAAAA==.Pettacular:BAABNQAECn8nAAIPAAgK3RlKYwBMAgAPAAgK3RlKYwBMAgAAAA==.',
Ph='Phidra:BAABNQAECn8lAAMCAAgKzwZfmABGAQACAAgKzwZfmABGAQADAAYKxAGo7wCwAAAAAA==.',
Po='Poprocks:BAAANQAECgEIAQAAAA==.Potatogg:BAAANQAECgEIBAAAAA==.',
Pr='Predatorc:BAABNQAECn8aAAIPAAcKywb0vwB+AQAPAAcKywb0vwB+AQAAAA==.Primevil:BAAANQAECgYIBwAAAA==.Primevl:BAABNQAECn8dAAINAAgK4ArSTgCgAQANAAgK4ArSTgCgAQAAAA==.',
Py='Pyrissa:BAAANQABCgYIBgAAAA==.',
Qa='Qamar:BAAANQADCgMIAwAAAA==.',
Ra='Radïance:BAAANQAECgQIBAAAAA==.Raediant:BAAANQAECgcIEgAAAA==.Ragethecage:BAAANQADCgYIBwAAAA==.Raggaemon:BAAANQAECgYIEAAAAA==.Rahvinwulf:BAAANQADCgQJBAAAAA==.Raquel:BAABNQAECn8aAAICAAcKkgIRuQD1AAACAAcKkgIRuQD1AAAAAA==.',
Re='Readyfireaim:BAAANQAECgQIBAAAAA==.Rectaltremor:BAAANQADCgYIBgAAAA==.Rede:BAAANQAECgEIAQAAAA==.Reeyou:BAAANQADCgYICgABNQAECgYIEAAHAAAAAA==.Reign:BAAANQADCggIIwABNQAECgkJHwAEAGoMAA==.Relieff:BAAANQAECgEIAQAAAA==.Rennistus:BAAANQADCggJCAAAAA==.Revival:BAAANQADCgEIAQABNQAECgQIBgAHAAAAAA==.Reynax:BAAANQAECgMJAwAAAA==.',
Ri='Rio:BAABNQAECn8hAAIUAAgKlhJqNwDxAQAUAAgKlhJqNwDxAQAAAA==.Ris:BAABNQAECn8pAAMBAAgKdhmJsgAcAgABAAcKjRmJsgAcAgAFAAEKAxksPQBJAAAAAA==.Ritami:BAABNQAECn8aAAIaAAgKbCARFgCpAgAaAAgKbCARFgCpAgAAAA==.',
Ro='Roffy:BAABNQAECn8lAAIZAAgKlhELZwDfAQAZAAgKlhELZwDfAQAAAA==.Roknathar:BAABNQAECn8gAAMaAAkKECHcBgBgAwAaAAkKECHcBgBgAwAPAAEKAAD/TAFBAAAAAA==.',
Sa='Saerin:BAAANQAECgcIEgAAAA==.Saintmedes:BAAANQAECgQICAAAAA==.Sangoma:BAAANQADCgcJBwAAAA==.Sargeth:BAAANQAECgcIEgAAAA==.',
Se='Sechiwa:BAAANQADCgEIAQAAAA==.Sedo:BAAANQAECgIIBAAAAA==.Sehlia:BAABNQAECn8qAAIGAAkKiBPfWQBFAgAGAAkKiBPfWQBFAgAAAA==.Selarae:BAAANQADCggICAABNQAECggIGgAaAGwgAA==.Selenis:BAAANQAECgMIAwABNQAECggIJwALANslAA==.',
Sh='Shadowlady:BAAANQAECgEIAQAAAA==.Shadowmonarc:BAAANQAECgQICAAAAA==.Shadowwizard:BAAANQAECgcIEgABNQAECggIFAARAOYZAA==.Shamania:BAAANQAECgIIBQABNQAECgYICQAHAAAAAA==.Shaomai:BAABNQAECn8jAAMDAAkKSxtPagDeAQADAAYK6hxPagDeAQACAAcKgRU6bgC9AQABNQAFFAIIBAAHAAAAAA==.Shariae:BAAANQADCgIIAgAAAA==.Sherminator:BAAANQADCgUICgAAAA==.Sheva:BAAANQAECgcICQABNQAECgkJHgAIAEEbAA==.Shidandfard:BAABNQAECn8kAAIBAAkKPyCrMgAlAwABAAkKPyCrMgAlAwAAAA==.Shifte:BAABNQAECn8jAAIYAAgK2g3YEgDOAQAYAAgK2g3YEgDOAQAAAA==.Shishkä:BAAANQAECgcICgAAAA==.Shiv:BAAANQADCggIFgABNQAECgIIAgAHAAAAAA==.Shockabeotch:BAAANQAECgYICQAAAA==.Shêrra:BAAANQADCgEIAQAAAA==.',
Si='Silverwin:BAAANQAECgIIAwAAAA==.',
Sk='Skorvrax:BAAANQAECgQIBQAAAA==.Skädi:BAAANQAECgQIBAAAAA==.',
Sl='Slaughter:BAAANQAECggIAwAAAA==.Slimage:BAABNQAECn8fAAIBAAgKyBjVlQBUAgABAAgKyBjVlQBUAgAAAA==.Slushius:BAAANQADCgEJAQAAAA==.',
Sm='Smittens:BAAANQADCggJDgAAAA==.',
Sn='Snakmag:BAAANQADCgQIBAAAAA==.',
So='Sorn:BAABNQAECn8aAAIcAAcKSQ6pMABWAQAcAAcKSQ6pMABWAQAAAA==.',
Sp='Spaarkle:BAAANQAECgUIDgAAAA==.Spectrehawk:BAAANQAECgEIAQABNQAFFAIIBQALAIwWAA==.Speçtre:BAACNQAFFH8FAAILAAIKjBapHwCIAAALAAIKjBapHwCIAAA1AAQKfy0AAgsACArRIf4YAOMCAAsACArRIf4YAOMCAAAA.',
St='Stheris:BAAANQADCgYJBgABNQAECgkJKAAfAB8LAA==.',
Su='Supak:BAAANQAECgQIBQAAAA==.Suppabad:BAABNQAECn8lAAISAAgKUhqkEQBfAgASAAgKUhqkEQBfAgAAAA==.',
['Sá']='Sákura:BAAANQADCgIIAgAAAA==.',
['Sâ']='Sâintdank:BAAANQAECggIBwAAAA==.',
['Så']='Såmæl:BAAANQADCgEIAQAAAA==.',
Ta='Taara:BAAANQAECgIJAgABNQAECggIIwAFAD8kAA==.Tadlight:BAAANQAECgIIBAAAAA==.Tarok:BAAANQADCgYIBgAAAA==.Tattooman:BAAANQABCgIIAQAAAA==.Tazara:BAAANQAECgQIBgAAAA==.',
Tb='Tbone:BAAANQADCgUJBQAAAA==.',
Te='Teapha:BAAANQAECgYIEAAAAA==.Ted:BAABNQAECn8fAAIDAAYKuR1kZQDtAQADAAYKuR1kZQDtAQAAAA==.Tehnegev:BAAANQAECgIIAwABNQAECgcIFwARAJ8XAA==.Teias:BAAANQAECgUIBQABNQAECgkJNAAIAAYZAA==.Temptressxx:BAAANQAECgUJDQAAAA==.Tenstar:BAAANQAECgMIAwAAAA==.',
Th='Thekingheals:BAAANQAECgYIDgABNQAECgkJGQAVAFQdAA==.Thokmay:BAAANQAECgIIAgAAAA==.Thorel:BAAANQADCgYIBgAAAA==.Thunden:BAAANQADCgYIEQAAAA==.Thunderon:BAAANQABCgEJAQAAAA==.',
Ti='Tiandrinna:BAABNQAECn8rAAMhAAkKORj9AQBVAgAhAAgKwRn9AQBVAgABAAkKRBH/nABGAgAAAA==.Tightywhitey:BAAANQABCgYIBwAAAA==.Tigirius:BAAANQAECgIIAgAAAA==.Timkaoss:BAAANQAECgEIAgAAAA==.Timmyjudge:BAAANQADCgcIBwAAAA==.',
Tm='Tmagnet:BAAANQAECgIIAwAAAA==.',
To='Tophats:BAAANQABCgcIDQAAAA==.Totemllord:BAAANQADCgYJBgAAAA==.Totemology:BAAANQADCgYJCQAAAA==.Tourmaline:BAAANQAECgEIAgABNQAECgkJKgAZAAcfAA==.',
Tr='Tripwire:BAAANQADCgQIBQAAAA==.Tritherelyn:BAAANQADCgYIBgAAAA==.',
Tw='Tweedildee:BAABNQAECn8lAAIFAAkKVRY3BwB9AgAFAAkKVRY3BwB9AgAAAA==.',
['Tà']='Tàttersail:BAAANQAECgMIAwAAAA==.',
Un='Unholycreep:BAAANQADCgIJAgABNQAECgYICQAHAAAAAA==.Unkindled:BAABNQAECn8UAAIRAAgK5hmaZwBhAgARAAgK5hmaZwBhAgAAAA==.',
Va='Valdor:BAABNQAECn8iAAIKAAgKJRPfNwDxAQAKAAgKJRPfNwDxAQAAAA==.Valicous:BAAANQADCggILAAAAA==.Vandalie:BAAANQAECgMIAwABNQAECggIEgAHAAAAAA==.Vaylorian:BAABNQAECn8mAAIJAAkKaiaHAAD4AwAJAAkKaiaHAAD4AwAAAA==.',
Ve='Velion:BAAANQADCgYIDQAAAA==.Vellathor:BAAANQADCgQIBQABNQAECgYIDAAHAAAAAA==.Velocity:BAAANQAECgYIDwAAAA==.Verianna:BAABNQAECn8nAAMLAAgK2yUaCQBwAwALAAgK2yUaCQBwAwAiAAYKVxQxcgBKAQAAAA==.',
Vi='Virelya:BAAANQADCgEIAQABNQAECgkJHwAEAGoMAA==.',
Vo='Vodkâshots:BAAANQAECggIEAAAAA==.Voidbinder:BAAANQAFFAIIBAAAAA==.',
Vu='Vulpixen:BAAANQAECgYIBwAAAA==.',
Wa='Wadumu:BAAANQAECgYICQAAAA==.Wampa:BAAANQADCgcIDAAAAA==.Warvegas:BAAANQAECgMIBQAAAA==.',
Wi='Willothewisp:BAAANQADCgUIBQAAAA==.Willowy:BAABNQAECn8jAAIFAAgKPyQ4AgBPAwAFAAgKPyQ4AgBPAwAAAA==.',
['Wâ']='Wâlmi:BAAANQAECgUIDwAAAA==.',
Xa='Xaerius:BAABNQAECn8lAAIMAAgKQQresQCbAQAMAAgKQQresQCbAQAAAA==.Xalatath:BAAANQADCgcIDQAAAA==.Xanda:BAAANQAECgcICAAAAA==.Xantyr:BAAANQAECgIIAgAAAA==.',
Ya='Yarman:BAAANQAECgIIAwAAAA==.',
Yo='Yojimbro:BAAANQAECgEIAgAAAA==.Yoshial:BAAANQAECgEIAQAAAA==.',
Za='Zaelen:BAAANQADCgQIBgAAAA==.Zainadin:BAAANQAECgMIBQAAAA==.Zalantir:BAAANQAECggIEAABNQAFFAUICgAaALsPAA==.Zariski:BAAANQAECgEIAQABNQAECgkJMQASAOgcAA==.Zarthus:BAAANQAECgMIAwAAAA==.',
Ze='Zealantis:BAAANQADCgQIBgAAAA==.Zealins:BAABNQAECn8XAAIRAAcKnxe8nADkAQARAAcKnxe8nADkAQAAAA==.',
Zi='Zirl:BAAANQAECgEIAgABNQAFFAUICgAaALsPAA==.Ziyn:BAACNQAFFH8KAAMaAAUKuw/uEQAaAQAaAAQKuw/uEQAaAQAPAAEKAAAUNQBOAAA1AAQKfzUAAw8ACQrqJD0HAKMDAA8ACQrRJD0HAKMDABoACAp5HTQgAEoCAAAA.',
Zo='Zoplete:BAAANQABCgIIBAAAAA==.',
['Án']='Ángél:BAAANQADCggICgAAAA==.',
['Ýa']='Ýachiru:BAAANQAECgUIBQAAAA==.',
['Ÿe']='Ÿeñnefer:BAAANQAECgEIAQAAAA==.',
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
