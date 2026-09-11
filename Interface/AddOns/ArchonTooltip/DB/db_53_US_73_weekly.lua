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

local lookup = {'Mage-Arcane','Unknown-Unknown','Evoker-Preservation','Priest-Shadow','Evoker-Devastation','Paladin-Retribution','Druid-Balance','Shaman-Elemental','DemonHunter-Devourer','Evoker-Augmentation','Shaman-Restoration','Monk-Brewmaster',}
local provider = {region='US',realm='Dragonmaw',name='US',type='weekly',zone=53,date='2026-09-08',data={Ah='Ahpuch:BAAANQAECgMIBgAAAA==.',
Ai='Aidasul:BAAANQADCggIEwAAAA==.',
Al='Aldesca:BAAANQADCggIEwAAAA==.',
An='Ancile:BAAANQADCgIIAgAAAA==.Anséis:BAAANQADCgQIBQAAAA==.Antury:BAAANQAECgUIBgAAAA==.',
Ar='Armstrõng:BAAANQAECgIIAgAAAA==.',
As='Ashpaw:BAAANQAECgcIDAAAAA==.Aspen:BAAANQADCggIDgAAAA==.',
At='Atcjedi:BAAANQAECgQIBgAAAA==.Atmospherewr:BAAANQAECgcIBwABNQAECgkJGgABAJMkAA==.Atmospherez:BAABNQAECoEaAAIBAAkJkySHCQByAwABAAkJkySHCQByAwAAAA==.',
Av='Avaniah:BAAANQAECgUIBgAAAA==.',
Az='Azmodan:BAAANQADCgcIBwAAAA==.Azuresky:BAAANQADCggICAAAAA==.',
Ba='Baalsdruid:BAAANQADCgYIDwAAAA==.Baep:BAAANQADCgUIBQAAAA==.Bandrago:BAAANQAECgIIAgAAAA==.',
Be='Beaulioh:BAAANQAECgIIAwAAAA==.Bekzarn:BAAANQAECgEIAQABNQAECgUIBwACAAAAAA==.Benfrank:BAAANQAECgIIAwAAAA==.Bernthul:BAAANQAECgEIAQAAAA==.Bethan:BAAANQAECgEIAQAAAA==.',
Bl='Blaart:BAAANQAECgYIDwAAAA==.Blackwaters:BAAANQAECgQIBQAAAA==.Blax:BAAANQADCgYIEgAAAA==.Blindcow:BAAANQAECgcICwAAAA==.Blindhugs:BAAANQAECgQIBQABNQAECgQIBgACAAAAAA==.Bllu:BAAANQADCgIIAgAAAA==.Bloodloss:BAAANQADCgYICQAAAA==.Blumez:BAAANQAECgUIBQAAAA==.Blùey:BAAANQADCgYIBgABNQAECgcIEAACAAAAAA==.',
Bo='Bodytypebig:BAAANQAECgYIDAAAAA==.Boicrystian:BAAANQADCgQICQAAAA==.Bolillo:BAAANQADCgcIBwABNQAECgIIAwACAAAAAA==.Bookitty:BAAANQADCggIEgAAAA==.Boosty:BAAANQAECgQICAAAAA==.Bossladìe:BAAANQAECgYICgAAAA==.',
Br='Brewholic:BAAANQADCgQIBAAAAA==.Bristle:BAAANQAECgUICAAAAA==.Brommix:BAAANQADCgMIBgAAAA==.',
Bu='Buex:BAAANQADCgEIAQAAAA==.Buhbles:BAAANQAECgcIDgAAAA==.Bullshiitake:BAAANQAECgYICwAAAA==.',
Ca='Calaglin:BAAANQAECgUICQAAAA==.Catstack:BAAANQADCgcIDQAAAA==.',
Ce='Celesti:BAAANQAECgQICAAAAA==.',
Ch='Chiky:BAAANQAECgIIAgAAAA==.Choom:BAAANQADCgUICgAAAA==.Chubsy:BAAANQAECggICAAAAA==.Chuckkyd:BAAANQAECgQICAAAAA==.',
Cl='Claugh:BAAANQAECgcIDAAAAA==.Cleb:BAAANQAECgcICAAAAA==.Clocker:BAAANQADCggIFAAAAA==.Clumbsykoala:BAAANQAECgIIAgAAAA==.',
Co='Coldlunch:BAAANQADCgQIBAAAAA==.Colton:BAABNQAECoEXAAIDAAkJcxH0CQBXAgADAAkJcxH0CQBXAgAAAA==.Combatcow:BAAANQAECgcICwAAAA==.Contagion:BAAANQAECggICAAAAA==.Cozmic:BAAANQAECgQICQAAAA==.',
Cr='Crucifixd:BAAANQAECgEIAQAAAA==.Crysteris:BAAANQADCgQICQAAAA==.',
Ct='Ctrlzr:BAAANQAECgQIBgAAAA==.',
Cu='Curandero:BAAANQAECgQICwAAAA==.Curie:BAAANQAECgEIAQABNQAECgYIDQACAAAAAA==.Cutiecow:BAAANQADCgIIAgAAAA==.',
Da='Dabeebo:BAAANQADCgUIBQAAAA==.Dameck:BAAANQAECgUICAAAAA==.Darkburley:BAAANQADCgMIAwAAAA==.Darosh:BAAANQADCgIIAgABNQAECgMIAwACAAAAAA==.Dasdots:BAAANQADCggIFwAAAA==.Dazzeler:BAAANQAECgMIAwAAAA==.',
De='Deanie:BAAANQABCgIIAwAAAA==.Deejaypaulyd:BAAANQAECgQIBQAAAA==.Delver:BAAANQAECgQIBQAAAA==.Demongirly:BAAANQABCgQIBAAAAA==.Denathria:BAAANQAECgUICQAAAA==.Derailed:BAAANQABCgIIAgAAAA==.Despir:BAABNQAECoEaAAIEAAkJNSKrAQChAwAEAAkJNSKrAQChAwAAAA==.',
Di='Dicspriest:BAAANQAECgEIAQAAAA==.',
Do='Doak:BAAANQAECgYIDQAAAA==.Doonfist:BAAANQABCgYICQAAAA==.Dottie:BAAANQADCggIGAAAAA==.Dotz:BAAANQAECgcIEQAAAA==.Douchec:BAAANQADCgIIAgAAAA==.',
Dr='Draconius:BAAANQADCgMIBgAAAA==.Dragonforce:BAAANQAECgEIAQAAAA==.Dragonhaze:BAAANQAECgIIAgAAAA==.Dragonskull:BAAANQADCgIIAgAAAA==.Drazentar:BAAANQAECgIIAgAAAA==.Drevox:BAAANQAECgQIBAAAAA==.Druiddruid:BAAANQADCgMIAwAAAA==.',
Du='Dulgar:BAAANQAECgUICAAAAA==.Dumami:BAAANQADCgIIAgAAAA==.',
['Dë']='Dëlilah:BAAANQADCgcICQAAAA==.',
Ea='Eaglewarrior:BAAANQADCggICAAAAA==.',
El='Elleduff:BAAANQAECgIIAgAAAA==.Elyssabeta:BAAANQADCgQIBAAAAA==.Elysstaa:BAAANQAECgUICAAAAA==.',
En='Entïty:BAAANQADCgcIDgAAAA==.',
Eo='Eogden:BAAANQAECgYICgAAAA==.',
Eq='Equilibria:BAAANQADCggIEwAAAA==.',
Er='Erida:BAAANQADCgYIBgABNQAECgIIAgACAAAAAA==.Ers:BAAANQADCgYIBgABNQAECgIIAwACAAAAAA==.',
Et='Etík:BAAANQADCggIEwAAAA==.',
Ev='Evocative:BAABNQAECoEXAAIFAAgJ3h6YBADsAgAFAAgJ3h6YBADsAgAAAA==.',
Ex='Exaltso:BAAANQADCgYICwAAAA==.',
Ey='Eyye:BAAANQADCgQIBgABNQAECgIIAgACAAAAAA==.',
Fa='Farns:BAAANQAFFAIIAwAAAA==.Fawndolynn:BAAANQAECgEIAQAAAA==.',
Fe='Felinepriest:BAAANQAECgQIBQAAAA==.Felovan:BAAANQADCgYIBgAAAA==.Felsoaked:BAAANQADCgMIAwAAAA==.Felstehr:BAAANQAECgIIAgAAAA==.',
Fi='Fiendish:BAAANQADCggIFQAAAA==.Filligri:BAAANQAECgcIDAAAAA==.Firebäne:BAAANQAECgQIBQAAAA==.Fistnor:BAAANQAECgEIAQAAAA==.',
Fl='Flaminghawk:BAAANQAFFAMIAwAAAA==.',
Fr='Franklin:BAAANQAECgIIAgAAAA==.Freakies:BAAANQADCgIIAgAAAA==.Freyin:BAAANQAECgUIBwAAAA==.Frolgar:BAAANQADCgMIAwAAAA==.',
Fu='Fullclangg:BAAANQAECggIDQABNQAFFAYIDAADABoaAA==.Fulldracarys:BAACNQAFFIEMAAIDAAYJGhqXAAAvAgADAAYJGhqXAAAvAgA1AAQKgRgAAgMACQnPItcBAGMDAAMACQnPItcBAGMDAAAA.Fullgabagool:BAAANQAECgYIEgABNQAFFAYIDAADABoaAA==.Fulltranq:BAAANQADCgEIAQABNQAFFAYIDAADABoaAA==.',
['Fø']='Føxzxv:BAAANQADCgMIAwAAAA==.',
Ga='Gamesucks:BAAANQADCgcIFAAAAA==.Gaya:BAAANQADCgIIAgAAAA==.',
Ge='Gettingowned:BAAANQADCgMIAwAAAA==.Getzapped:BAAANQADCgQIBQAAAA==.',
Gf='Gfoo:BAAANQADCgcIBwAAAA==.Gfoowar:BAAANQAECgUICAAAAA==.',
Gl='Glimpse:BAAANQABCgUIBgAAAA==.',
Gn='Gnomebody:BAAANQAECgEIAQAAAA==.Gnomicide:BAAANQADCgEIAQAAAA==.',
Go='Goattaco:BAAANQADCgYIBgAAAA==.Golddigger:BAAANQAECgQIBAAAAA==.',
Gr='Grimknight:BAABNQAECoEVAAIGAAkJNyY6AQDcAwAGAAkJNyY6AQDcAwAAAA==.',
Gu='Guycow:BAAANQAECggIEgAAAA==.',
Ha='Hambonë:BAACNQAFFIEKAAIHAAYJDB9oAABTAgAHAAYJDB9oAABTAgA1AAQKgRkAAgcACQnTJaMAAN8DAAcACQnTJaMAAN8DAAAA.Hardballs:BAAANQADCgUIBgAAAA==.Hashbrowns:BAAANQAECgQIBwAAAA==.Havdk:BAEANQAECgIIAwAAAA==.Haxxorwyn:BAAANQAECgEIAQAAAA==.Hazreil:BAAANQAECgUICAAAAA==.',
He='Healzyew:BAAANQADCgQIBAAAAA==.Heartlust:BAAANQAECgYIDgAAAA==.Heavenlee:BAAANQAECgIIAgABNQADCggIDgACAAAAAA==.Hecklefish:BAAANQAECgcIDgAAAA==.Heretic:BAAANQAECgEIAQAAAA==.',
Hi='Hierro:BAAANQAECgQIBAAAAA==.Highdegrees:BAAANQADCggIDAAAAA==.Hitagi:BAAANQAECgIIBQAAAA==.',
Ho='Holyblasts:BAAANQAECgQIBAAAAA==.Holyfreaks:BAAANQADCggIDQAAAA==.Holyskreep:BAAANQABCgMIBAABNQADCgIIAQACAAAAAA==.Horsey:BAAANQAECgYIBgABNQAECggIDwACAAAAAA==.Hownow:BAAANQADCgIIAgAAAA==.',
Hu='Hummingbird:BAAANQADCgQICQABNQAECgUICQACAAAAAA==.Hungus:BAAANQADCggIFgAAAA==.Hurtszick:BAAANQADCgIIAgAAAA==.',
Hy='Hydrotiger:BAAANQADCgIIAgABNQAECggIEwACAAAAAA==.',
['Hä']='Härasou:BAAANQADCgQIBgAAAA==.',
Il='Illiturtle:BAAANQAECgQIBwAAAA==.',
In='Indigolemon:BAAANQAECgYIBwAAAA==.Inkenhancer:BAAANQAECgQIBQAAAA==.',
Io='Iowned:BAAANQAECgIIAgAAAA==.',
Ja='Jamie:BAAANQADCgcIDAAAAA==.',
Jo='Jollyollie:BAAANQADCgMIAwAAAA==.',
Ju='Judojudy:BAAANQAECgEIAQAAAA==.June:BAAANQADCgEIAQAAAA==.',
['Jô']='Jôker:BAAANQAECgIIAgAAAA==.',
Ka='Kacho:BAAANQAECgEIAQAAAA==.Kaelara:BAAANQADCggICAAAAA==.Kaladin:BAAANQAECgQIBAAAAA==.Kappo:BAAANQAECgEIAQAAAA==.Kathorall:BAAANQAECgQIBwAAAA==.Kawaiihealer:BAAANQAECgQICAAAAA==.',
Ke='Keddy:BAAANQADCgQICAAAAA==.Keddyl:BAAANQADCgMIAwAAAA==.Kemper:BAAANQAECgIIAgAAAA==.Kerrs:BAAANQAECgEIAQAAAA==.',
Ki='Kidneypopper:BAAANQADCgcICAABNQAECgQICQACAAAAAA==.Kievit:BAAANQAECgEIAQAAAA==.Kir:BAAANQAECgEIAQAAAA==.Kittana:BAAANQAECgQIBAAAAA==.',
Kk='Kkelhus:BAAANQADCgUIBQAAAA==.Kkrantuq:BAAANQAECgUIBwAAAA==.',
Kl='Klarityx:BAAANQAECgcIBwAAAA==.',
Kn='Knownentity:BAAANQADCgEIAQABNQADCgcIDgACAAAAAA==.',
Ko='Koma:BAAANQADCggICAABNQAECgkJGQAIAFImAA==.Komatos:BAABNQAECoEZAAIIAAkJUiZUAAD3AwAIAAkJUiZUAAD3AwAAAA==.Koreantacos:BAAANQADCgcIBwAAAA==.Koronus:BAAANQADCgYICQAAAA==.',
Kr='Kracklin:BAAANQADCgYIBgAAAA==.',
Ks='Ks:BAAANQADCgMIBgABNQAECgIIAgACAAAAAA==.',
Ku='Kurisutina:BAAANQAECgQIBAAAAA==.',
['Kê']='Kênsêi:BAAANQAECgQICAAAAA==.',
['Kô']='Kôan:BAAANQADCgcICQAAAA==.',
La='Lanathel:BAAANQADCgUIBQAAAA==.',
Le='Leafyjoe:BAAANQAECgQIBQAAAA==.Legendarybob:BAAANQADCgYIBwAAAA==.Legofortnite:BAAANQADCgYIBgAAAA==.Legomyeggö:BAAANQAECgYICgAAAA==.Legö:BAAANQADCgYICAABNQAECgYICgACAAAAAA==.',
Lh='Lhera:BAAANQADCggICAABNQAECgQIBgACAAAAAA==.',
Li='Lido:BAAANQAECggICAAAAA==.Lildeemon:BAAANQAECgUICQAAAA==.Lilspyro:BAAANQAECgMIAwAAAA==.Livathian:BAAANQAECgUIBwAAAA==.',
Lo='Lokrah:BAAANQABCgMIBAAAAA==.',
Lu='Lunavel:BAAANQAECgUICwAAAA==.',
Ly='Lydo:BAAANQAECggICwAAAA==.',
Ma='Magicdan:BAAANQADCgYIBwAAAA==.Magicfrank:BAAANQAECgYICQAAAA==.Malnorr:BAAANQAECgQIBAAAAA==.Mandragon:BAAANQADCgUIBQABNQAECggIEgACAAAAAA==.Mangol:BAAANQAECgcIBwAAAA==.Maryillo:BAABNQAECoEaAAIHAAkJviOfAwCBAwAHAAkJviOfAwCBAwAAAA==.',
Mc='Mcmannis:BAAANQADCggICAAAAA==.Mcpoltrain:BAAANQADCgUICQAAAA==.',
Me='Mennil:BAAANQADCggIEwAAAA==.Meolater:BAAANQAECgQIBgAAAA==.Mesmerise:BAAANQADCgcIEAABNQADCggICAACAAAAAA==.',
Mi='Micotte:BAAANQADCgUIBQABNQAECgQIBgACAAAAAA==.Mindgoblinn:BAAANQAECgEIAQAAAA==.Minyaw:BAAANQADCgYIBQABNQAECgYIDQACAAAAAA==.Mishrakthul:BAAANQADCgQIBQAAAA==.Missfearfact:BAAANQAECgEIAQAAAA==.',
Mm='Mmchocolat:BAAANQADCgIIAgAAAA==.',
Mo='Mog:BAAANQABCgIIAgAAAA==.Mokari:BAEANQAECgUICAAAAA==.Moolissa:BAAANQAECgQIBAAAAA==.Moonan:BAAANQADCgQIAQAAAA==.Moonk:BAAANQAECgEIAwAAAA==.Morbidchaos:BAABNQAECoEZAAIJAAkJ4SAdBABbAwAJAAkJ4SAdBABbAwAAAA==.Morkels:BAAANQAECgcIDAABNQAFFAcICwAKAAsbAA==.',
Mu='Muddyshark:BAAANQAECgUIBQAAAA==.Mukatsuku:BAAANQAECgEIAQAAAA==.',
My='Mykhawk:BAAANQADCgIIAwAAAA==.',
Na='Naeth:BAAANQAECgUIBwAAAA==.Nalrot:BAAANQADCggICAAAAA==.Narcine:BAAANQADCgYIBgAAAA==.',
Ne='Neciecakes:BAAANQAECgUICAAAAA==.Nee:BAABNQAECoEWAAILAAkJHhDhFwBMAgALAAkJHhDhFwBMAgAAAA==.Nekorai:BAAANQADCgIIAgAAAA==.Nelor:BAAANQAECgIIAwAAAA==.Nextgame:BAAANQAECgIIBAAAAA==.',
Ni='Nisona:BAAANQADCgcIEwAAAA==.Nitashal:BAAANQAECgcIDQAAAA==.',
No='Noremac:BAAANQADCgYIDAAAAA==.',
Nu='Nubsaiboot:BAAANQADCgMIAwABNQAECgEIAQACAAAAAA==.',
Ny='Nythariel:BAAANQADCgcICgAAAA==.',
Od='Odi:BAAANQADCgcIEgAAAA==.',
Ok='Okiaat:BAAANQADCgIIAgAAAA==.',
Ol='Oliviawildè:BAAANQAECgYICQAAAA==.',
On='Onlyfrans:BAAANQAECgIIAgAAAA==.',
Or='Orcnado:BAAANQAECgEIAQAAAA==.',
Pa='Pakoh:BAAANQAECgUIBwAAAA==.Pallyforhire:BAAANQADCgYIEAAAAA==.Pantyblossom:BAAANQAECgEIAQAAAA==.',
Pe='Peaches:BAAANQAECgIIAgAAAA==.Pegaiai:BAAANQAECgMIAwAAAA==.Pegasus:BAAANQAECgMICQAAAA==.Pelito:BAAANQABCgQIAgAAAA==.Pelo:BAAANQADCgEIAQAAAA==.Pewpewz:BAAANQADCgUICwABNQAECgUIBwACAAAAAA==.',
Ph='Phaeddrus:BAAANQAECgIIAgAAAA==.Phrix:BAAANQADCgYIBgABNQAECgcIDgACAAAAAA==.',
Pi='Pinecone:BAAANQAECgcIEwAAAA==.',
Pl='Ploppster:BAAANQADCggICAAAAA==.Plot:BAAANQAECgEIAQAAAA==.',
Po='Poekimaw:BAAANQADCgYICgAAAA==.Pokï:BAAANQADCgUICQAAAA==.Polpo:BAAANQAECgcIDgAAAA==.Poppinin:BAAANQAECgEIAQAAAA==.Potaters:BAAANQADCgQIBAAAAA==.Potshotbot:BAAANQADCgYIBgAAAA==.Powerwordhug:BAAANQAECgQIBgAAAA==.',
Pr='Praedo:BAAANQADCgYIBgAAAA==.',
Ps='Psychaos:BAAANQADCgUIBQAAAA==.Psychostorm:BAAANQAECgEIAQAAAA==.Psychritic:BAAANQAECgUIBQAAAA==.Psyence:BAAANQADCgQIBwAAAA==.',
Pu='Pukefist:BAAANQABCgIIAgAAAA==.Purge:BAAANQADCgMIAwAAAA==.Purrsnikitty:BAAANQADCggIDgAAAA==.Pus:BAAANQADCgYIBgAAAA==.',
Qu='Quillmane:BAAANQADCggIFgABNQAECgcIDgACAAAAAA==.Quzaster:BAAANQADCgYIBwAAAA==.',
Ra='Ragebate:BAAANQAECgUICAAAAA==.Ragingdeath:BAAANQADCgEIAQAAAA==.Rainakamugi:BAAANQAECgMIAwABNQAECgcIDQACAAAAAA==.Rakido:BAAANQADCgUIBQAAAA==.Rakkesh:BAAANQADCggIEwAAAA==.Ralphanir:BAAANQAECgIIAgAAAA==.Raskreia:BAAANQADCggICQAAAA==.Rayvoker:BAAANQADCgYIBgABNQAECgUICgACAAAAAA==.',
Re='Reek:BAAANQAECgQIBAAAAA==.Rexari:BAAANQAECgQIBAAAAA==.Rezmae:BAAANQAECgEIAQAAAA==.',
Ri='Riniedaze:BAAANQADCgUICgAAAA==.',
Ro='Rockandstone:BAAANQAECggIEwAAAA==.Rooty:BAAANQADCgIIAwAAAA==.',
Sa='Safetyspork:BAAANQAECgIIAgAAAA==.Sagë:BAAANQAECgEIAgAAAA==.Sakonutz:BAAANQAECgIIAgAAAA==.Saresh:BAAANQADCgcIBwAAAA==.Sauron:BAAANQADCgQIBAAAAA==.',
Se='Seasonedbeef:BAAANQAECgIIAgAAAA==.Sehl:BAAANQADCgUIBQAAAA==.Sejien:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Sendh:BAAANQADCggIFQAAAA==.Sermet:BAAANQAECgEIAQAAAA==.Sermonn:BAAANQADCgcIDQAAAA==.Serous:BAAANQADCggIFgAAAA==.Seshin:BAAANQAECgcIEwAAAQ==.Setal:BAAANQAECgcIDgAAAA==.',
Sh='Shaeman:BAAANQADCgUIBQABNQAECgYIDQACAAAAAA==.Shammoo:BAAANQADCgEIAQAAAA==.Shcho:BAAANQABCgEIAQAAAA==.Sheepe:BAAANQADCggIFQAAAA==.Sheriff:BAAANQAECggIBgAAAA==.Shinydude:BAAANQADCgMIAwAAAA==.Shinyscalp:BAAANQAECgQIBAAAAA==.Shogunz:BAAANQADCggICAAAAA==.',
Si='Simaria:BAAANQADCgYIBgAAAA==.Sinapaladin:BAAANQAECgEIAQABNQAECgEIAQACAAAAAA==.Siomara:BAAANQADCggICAAAAA==.Sivart:BAAANQADCgIIAgAAAA==.',
Sk='Skreep:BAAANQADCgIIAQAAAA==.',
Sl='Slabbster:BAAANQAECgEIAQAAAA==.',
Sm='Smooshednewt:BAAANQAECggIEwAAAA==.',
Sn='Sne:BAAANQADCgYIEAAAAA==.',
So='Soloa:BAAANQADCgcIBwAAAA==.Soo:BAAANQADCgEIAQAAAA==.Sophira:BAAANQAECgYICwAAAA==.Sosneaky:BAAANQADCgMIBgAAAA==.Soulfuria:BAAANQAECgcIBwAAAA==.',
Sp='Spekk:BAAANQADCgQIBAAAAA==.Speknawz:BAAANQAECgUICQAAAA==.Splatzill:BAAANQADCgIIAgABNQAECgcIDAACAAAAAA==.Spoiledangel:BAAANQAECgIIAgAAAA==.Spoonhat:BAAANQADCgYICgABNQAECgIIAgACAAAAAA==.Springz:BAAANQAECgUICAAAAA==.',
Sr='Srwednesday:BAAANQABCgQIBAAAAA==.',
St='Staggering:BAAANQAECgQIBAAAAA==.Starryniight:BAAANQADCggIDgAAAA==.Stephsux:BAAANQAECgIIAgAAAA==.Stickers:BAAANQAECgEIAQAAAA==.',
Su='Suetang:BAAANQADCgQIBAAAAA==.Suhgarro:BAAANQAECgEIAQAAAA==.Suika:BAAANQAECgQIBAAAAA==.Supanova:BAAANQAECgMIAwABNQAECggIEwACAAAAAA==.',
Sv='Svelus:BAABNQAECoEYAAIGAAkJESX4AQDGAwAGAAkJESX4AQDGAwAAAA==.',
Sw='Swingin:BAAANQAECgQIBQAAAA==.',
Sy='Sycophancy:BAAANQADCgQIBAAAAA==.Synaptichole:BAAANQADCggIEwAAAA==.Syroka:BAAANQADCgYIBgAAAA==.',
Ta='Tachealz:BAAANQADCggICAABNQAECgIIAgACAAAAAA==.Tartan:BAAANQAECgQIBQAAAA==.Taurenmill:BAAANQADCgIIAgAAAA==.',
Te='Techi:BAAANQADCgIIAgAAAA==.Temres:BAAANQADCgcIBwABNQAECgEIAQACAAAAAA==.Tendermulva:BAAANQAECgUICQAAAA==.Terekk:BAAANQADCgUICAAAAA==.',
Th='Theod:BAAANQADCgYIBgAAAA==.Thesauce:BAAANQAECggIEgAAAA==.Thimo:BAAANQADCgEIAQABNQADCggICQACAAAAAA==.Thrikal:BAAANQAECgUICAAAAA==.',
To='Tomsmg:BAAANQAECgYICQAAAA==.Toofs:BAAANQAECgIIAwAAAA==.Toxifay:BAAANQADCggIFQAAAA==.',
Tr='Traell:BAAANQADCgYIDAABNQAECgQICAACAAAAAA==.Treehuggles:BAAANQADCgUIBQABNQAECgQIBgACAAAAAA==.Truedat:BAAANQADCgQIBwAAAA==.',
Ug='Ughtismo:BAAANQADCgUIBQAAAA==.',
Us='Usagiknight:BAAANQAECgYICgAAAA==.Ushii:BAAANQAECgIIAgAAAA==.',
Va='Valei:BAAANQADCgYICwAAAA==.',
Vi='Vinda:BAAANQAECgUICAAAAA==.Vivixia:BAAANQAECgYICQAAAA==.',
Vo='Voodoolock:BAAANQAECgIIAgAAAA==.',
Wa='Wallo:BAAANQAECgUIBwAAAA==.Washedbolt:BAAANQADCgYIBgAAAA==.Washedpyro:BAAANQADCgYICwAAAA==.Washedzebu:BAAANQAECgUICgAAAA==.Wayfairkid:BAAANQADCgUIBQAAAA==.',
We='Weeb:BAACNQAFFIELAAIKAAcJCxsLAACzAgAKAAcJCxsLAACzAgA1AAQKgRoAAwoACQmzJU4AAKkDAAoACQmzJU4AAKkDAAUACAmQGlkIAFwCAAAA.',
Wh='Whiterabbitt:BAAANQADCgYIBgAAAA==.Whynotlock:BAAANQADCgEIAQAAAA==.',
Wi='Willywonkas:BAAANQADCggIDAAAAA==.Wilmabfiymr:BAAANQAECgEIAQAAAA==.',
Wo='Woa:BAAANQADCggIEgAAAA==.Woofwoofwoof:BAAANQADCggIGAAAAA==.',
['Wà']='Wàll:BAAANQAECgEIAQAAAA==.',
Xi='Xiolan:BAAANQAECgEIAQABNQAECgcIEAACAAAAAA==.',
Ye='Yeeloow:BAAANQADCgIIAgAAAA==.',
Ys='Yshaarj:BAAANQADCggICgAAAA==.',
Yu='Yulok:BAABNQAECoEaAAIMAAkJkyYUAAADBAAMAAkJkyYUAAADBAAAAA==.Yuukí:BAAANQADCggICAABNQAECgcIEAACAAAAAA==.',
Za='Zaberra:BAAANQAECgIIAgABNQAECgYICwACAAAAAA==.Zanarkand:BAAANQAECgMIAwAAAA==.Zaphoof:BAAANQADCgQIBAAAAA==.Zarb:BAAANQAECgEIAQAAAA==.Zardukari:BAAANQADCgQIBAAAAA==.',
Ze='Zexexe:BAAANQAECgYIBwABNQAFFAYICgAHAAwfAA==.',
Zi='Zibroth:BAAANQAECgQIBQAAAA==.Zieg:BAAANQAECgUIBQAAAA==.Zina:BAAANQAECgIIAgAAAA==.',
['Ëv']='Ëvïl:BAAANQADCgMIAwAAAA==.',
['Ëy']='Ëyë:BAAANQADCgIIAgAAAA==.',
['Ýu']='Ýuuki:BAAANQAECgcIEAAAAA==.',
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
